import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

interface SubmitGuessData {
  date?: unknown;
  drawerId?: unknown;
  guess?: unknown;
  hintsUsed?: unknown;
}

interface SubmitGuessResult {
  correct: boolean;
  attempts: string[];
  finished: boolean;
  solvedOnAttempt: number | null;
  revealedWord: string | null;
}

function asNonEmptyString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0
    ? value
    : undefined;
}

const norm = (s: string): string => s.trim().toLowerCase();

const MAX_ATTEMPTS = 3;

export const submitGuess = onCall<SubmitGuessData, Promise<SubmitGuessResult>>(
  { region: 'us-central1' },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const date = asNonEmptyString(request.data?.date);
    const drawerId = asNonEmptyString(request.data?.drawerId);
    const guess = asNonEmptyString(request.data?.guess);
    if (!date || !drawerId || !guess) {
      throw new HttpsError('invalid-argument', 'A guess is required.');
    }
    if (drawerId === callerUid) {
      throw new HttpsError('invalid-argument', "You can't guess your own drawing.");
    }

    // Number of progressive hints the guesser used (0..3); sanitized to an int.
    const rawHints = request.data?.hintsUsed;
    const hintsUsed =
      typeof rawHints === 'number' && Number.isFinite(rawHints)
        ? Math.min(3, Math.max(0, Math.trunc(rawHints)))
        : 0;

    const guessId = `${callerUid}_${drawerId}`;
    const db = getFirestore();

    const privateRef = db.doc(`rounds/${date}/players/${drawerId}/private/round`);
    const playerRef = db.doc(`rounds/${date}/players/${drawerId}`);
    const guessRef = db.doc(`rounds/${date}/guesses/${guessId}`);

    const [privateSnap, playerSnap, existingSnap] = await Promise.all([
      privateRef.get(),
      playerRef.get(),
      guessRef.get(),
    ]);

    const chosenWord = asNonEmptyString(privateSnap.data()?.chosenWord);
    const hasSubmittedDrawing = playerSnap.data()?.hasSubmittedDrawing === true;
    if (!hasSubmittedDrawing || !chosenWord) {
      throw new HttpsError(
        'failed-precondition',
        "This drawing isn't ready to guess yet.",
      );
    }

    const existing = existingSnap.data();
    const existingAttempts = Array.isArray(existing?.attempts)
      ? (existing?.attempts as unknown[]).filter(
          (a): a is string => typeof a === 'string',
        )
      : [];
    const existingCorrect = existing?.correct === true;
    const existingSolvedOnAttempt =
      typeof existing?.solvedOnAttempt === 'number'
        ? existing.solvedOnAttempt
        : null;

    // Idempotent: a finished guess (solved or out of attempts) is never
    // re-appended, so re-submits can't bypass the attempt cap.
    if (existingCorrect || existingAttempts.length >= MAX_ATTEMPTS) {
      return {
        correct: existingCorrect,
        attempts: existingAttempts,
        finished: true,
        solvedOnAttempt: existingSolvedOnAttempt,
        revealedWord: chosenWord,
      };
    }

    const newAttempts = [...existingAttempts, guess];
    const correct = norm(guess) === norm(chosenWord);
    const solvedOnAttempt = correct ? newAttempts.length : existingSolvedOnAttempt;
    const finished = correct || newAttempts.length >= MAX_ATTEMPTS;

    const batch = db.batch();
    batch.set(guessRef, {
      guesserId: callerUid,
      drawerId,
      attempts: newAttempts,
      correct,
      solvedOnAttempt,
      hintsUsed,
      completedAt: finished ? FieldValue.serverTimestamp() : null,
      revealedWord: finished ? chosenWord : null,
    });

    // Lifetime guessing stats: increment the guesser's totals exactly once,
    // on the finishing transition (this append makes the guess finished).
    if (finished) {
      const guessStats: Record<string, FirebaseFirestore.FieldValue> = correct
        ? {
            correct: FieldValue.increment(1),
            [`win${solvedOnAttempt}`]: FieldValue.increment(1),
          }
        : {
            failed: FieldValue.increment(1),
          };
      // Lifetime hints-used total, incremented once per finished guess.
      guessStats.hintsUsed = FieldValue.increment(hintsUsed);
      batch.set(
        db.doc(`users/${callerUid}`),
        { guessStats },
        { merge: true },
      );
    }

    await batch.commit();

    return {
      correct,
      attempts: newAttempts,
      finished,
      solvedOnAttempt,
      revealedWord: finished ? chosenWord : null,
    };
  },
);
