import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

function asString(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function asBool(value: unknown): boolean {
  return value === true;
}

export const onDrawingSubmitted = onDocumentWritten(
  {
    document: 'rounds/{date}/players/{drawerId}',
    region: 'us-central1',
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Fire only when hasSubmittedDrawing flips from absent/false to true.
    const wasSubmitted = asBool(before?.hasSubmittedDrawing);
    const isSubmitted = asBool(after?.hasSubmittedDrawing);
    if (wasSubmitted || !isSubmitted) {
      return;
    }

    const drawerId = event.params.drawerId;
    const db = getFirestore();
    const drawerSnap = await db.doc(`users/${drawerId}`).get();
    const drawerData = drawerSnap.data();
    if (!drawerData) {
      logger.warn('Drawer user doc missing', { drawerId });
      return;
    }

    const drawerName = asString(drawerData.displayName) ?? 'A friend';
    const friendIds = Array.isArray(drawerData.friendIds)
      ? (drawerData.friendIds as unknown[]).filter(
          (id): id is string => typeof id === 'string',
        )
      : [];
    if (friendIds.length === 0) {
      return;
    }

    const tokens: string[] = [];
    const friendSnaps = await db.getAll(
      ...friendIds.map((id) => db.doc(`users/${id}`)),
    );
    for (const snap of friendSnaps) {
      const token = asString(snap.data()?.fcmToken);
      if (token) {
        tokens.push(token);
      }
    }
    if (tokens.length === 0) {
      return;
    }

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'New drawing!',
        body: `${drawerName} submitted a drawing! Can you guess it?`,
      },
      data: { route: '/feed' },
    });
    logger.info('Sent drawing-submitted notifications', {
      drawerId,
      count: tokens.length,
    });
  },
);

export const onGuessCorrect = onDocumentWritten(
  {
    document: 'rounds/{date}/guesses/{guessId}',
    region: 'us-central1',
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Fire only when correct flips from absent/false to true.
    const wasCorrect = asBool(before?.correct);
    const isCorrect = asBool(after?.correct);
    if (wasCorrect || !isCorrect) {
      return;
    }

    const date = event.params.date;
    const guessId = event.params.guessId;
    const drawerId = asString(after?.drawerId);
    const guesserId = asString(after?.guesserId);
    if (!drawerId || !guesserId) {
      logger.warn('Guess missing drawerId/guesserId', { guessId });
      return;
    }

    // Defense against forged guesses: the client self-asserts `correct`, so do
    // NOT trust it. Verify the doc identity and re-check correctness against the
    // drawer's real round before notifying anyone. Otherwise an attacker could
    // write a guess doc with correct:true and an arbitrary drawerId to spam
    // "X guessed your drawing!" pushes at any user.
    if (guessId !== `${guesserId}_${drawerId}`) {
      logger.warn('Guess id does not match its guesserId/drawerId', { guessId });
      return;
    }
    if (guesserId === drawerId) {
      return;
    }

    const db = getFirestore();
    const roundSnap = await db.doc(`rounds/${date}/players/${drawerId}`).get();
    const round = roundSnap.data();
    const chosenWord = asString(round?.chosenWord);
    if (!asBool(round?.hasSubmittedDrawing) || !chosenWord) {
      logger.warn('Guess targets a drawer with no submitted drawing', {
        guessId,
      });
      return;
    }

    const attempts = Array.isArray(after?.attempts)
      ? (after?.attempts as unknown[]).filter(
          (a): a is string => typeof a === 'string',
        )
      : [];
    const norm = (s: string): string => s.trim().toLowerCase();
    const actuallyCorrect = attempts.some((a) => norm(a) === norm(chosenWord));
    if (!actuallyCorrect) {
      logger.warn('Guess marked correct but no attempt matches chosenWord', {
        guessId,
      });
      return;
    }

    const drawerSnap = await db.doc(`users/${drawerId}`).get();
    const token = asString(drawerSnap.data()?.fcmToken);
    if (!token) {
      return;
    }

    const guesserSnap = await db.doc(`users/${guesserId}`).get();
    const guesserName =
      asString(guesserSnap.data()?.displayName) ?? 'Someone';

    await getMessaging().sendEachForMulticast({
      tokens: [token],
      notification: {
        title: 'Guessed!',
        body: `${guesserName} guessed your drawing!`,
      },
      // Recipient is the drawer; send them to the daily results summary.
      data: { route: '/results' },
    });
    logger.info('Sent guess-correct notification', { drawerId, guessId });
  },
);
