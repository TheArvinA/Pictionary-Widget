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
    const date = event.params.date;
    const db = getFirestore();
    const drawerRef = db.doc(`users/${drawerId}`);

    // Idempotency claim (mirrors streak.ts): toggling hasSubmittedDrawing
    // false->true could otherwise re-fire this trigger and spam the multicast.
    // Claim the day in a transaction; bail if already notified today. Reuse the
    // same snapshot for the drawer's name/friendIds to avoid a duplicate read.
    const claim = await db.runTransaction(async (tx) => {
      const drawerSnap = await tx.get(drawerRef);
      const drawerData = drawerSnap.data();
      if (!drawerData) {
        logger.warn('Drawer user doc missing', { drawerId });
        return null;
      }
      if (drawerData.lastDrawingNotifiedDate === date) {
        return null;
      }
      tx.update(drawerRef, { lastDrawingNotifiedDate: date });
      const friendIds = Array.isArray(drawerData.friendIds)
        ? (drawerData.friendIds as unknown[]).filter(
            (id): id is string => typeof id === 'string',
          )
        : [];
      return {
        drawerName: asString(drawerData.displayName) ?? 'A friend',
        friendIds,
      };
    });
    if (!claim || claim.friendIds.length === 0) {
      return;
    }
    const { drawerName, friendIds } = claim;

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

    const guessId = event.params.guessId;
    const drawerId = asString(after?.drawerId);
    const guesserId = asString(after?.guesserId);
    if (!drawerId || !guesserId) {
      logger.warn('Guess missing drawerId/guesserId', { guessId });
      return;
    }

    // Guesses are now admin-written only by the submitGuess callable, which
    // already validated correctness against the drawer's secret word. We keep
    // the identity checks so a (hypothetical) malformed doc can't aim a
    // "X guessed your drawing!" push at an arbitrary victim.
    if (guessId !== `${guesserId}_${drawerId}`) {
      logger.warn('Guess id does not match its guesserId/drawerId', { guessId });
      return;
    }
    if (guesserId === drawerId) {
      return;
    }

    const db = getFirestore();
    const drawerSnap = await db.doc(`users/${drawerId}`).get();
    const token = asString(drawerSnap.data()?.fcmToken);
    if (!token) {
      return;
    }

    const guesserSnap = await db.doc(`users/${guesserId}`).get();
    const guesserName =
      asString(guesserSnap.data()?.displayName) ?? 'Someone';

    await getMessaging().send({
      token,
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
