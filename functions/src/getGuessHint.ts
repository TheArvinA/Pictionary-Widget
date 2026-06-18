import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

interface GetGuessHintData {
  date?: unknown;
  drawerId?: unknown;
}

interface GetGuessHintResult {
  wordLength: number;
  firstLetter: string;
}

function asNonEmptyString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0
    ? value
    : undefined;
}

export const getGuessHint = onCall<GetGuessHintData, Promise<GetGuessHintResult>>(
  { region: 'us-central1' },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const date = asNonEmptyString(request.data?.date);
    const drawerId = asNonEmptyString(request.data?.drawerId);
    if (!date || !drawerId) {
      throw new HttpsError('invalid-argument', 'A hint request is invalid.');
    }
    if (drawerId === callerUid) {
      throw new HttpsError(
        'invalid-argument',
        "You can't get a hint for your own drawing.",
      );
    }

    const db = getFirestore();
    const privateRef = db.doc(`rounds/${date}/players/${drawerId}/private/round`);
    const playerRef = db.doc(`rounds/${date}/players/${drawerId}`);

    const [privateSnap, playerSnap] = await Promise.all([
      privateRef.get(),
      playerRef.get(),
    ]);

    const chosenWord = asNonEmptyString(privateSnap.data()?.chosenWord);
    const hasSubmittedDrawing = playerSnap.data()?.hasSubmittedDrawing === true;
    if (!hasSubmittedDrawing || !chosenWord) {
      throw new HttpsError(
        'failed-precondition',
        "This drawing isn't ready to guess yet.",
      );
    }

    const trimmed = chosenWord.trim();
    return {
      wordLength: trimmed.length,
      firstLetter: trimmed.charAt(0).toUpperCase(),
    };
  },
);
