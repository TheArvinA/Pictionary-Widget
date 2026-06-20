import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

function asBool(value: unknown): boolean {
  return value === true;
}

/**
 * Compute the previous UTC day for a 'yyyy-MM-dd' date string.
 */
function previousUtcDay(date: string): string {
  const [y, m, d] = date.split('-').map((part) => Number(part));
  const utc = new Date(Date.UTC(y, m - 1, d));
  utc.setUTCDate(utc.getUTCDate() - 1);
  const py = utc.getUTCFullYear();
  const pm = String(utc.getUTCMonth() + 1).padStart(2, '0');
  const pd = String(utc.getUTCDate()).padStart(2, '0');
  return `${py}-${pm}-${pd}`;
}

export const onDrawingStreak = onDocumentWritten(
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

    const date = event.params.date;
    const drawerId = event.params.drawerId;
    const prevDay = previousUtcDay(date);

    const db = getFirestore();
    const userRef = db.doc(`users/${drawerId}`);

    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const userData = userSnap.data();
      if (!userData) {
        logger.warn('Drawer user doc missing for streak', { drawerId });
        return;
      }

      const lastPlayedDate =
        typeof userData.lastPlayedDate === 'string'
          ? userData.lastPlayedDate
          : null;

      // Idempotent: already counted today.
      if (lastPlayedDate === date) {
        return;
      }

      const currentStreak =
        typeof userData.streakCount === 'number' ? userData.streakCount : 0;

      let nextStreak: number;
      if (lastPlayedDate === prevDay) {
        nextStreak = currentStreak + 1;
      } else {
        nextStreak = 1;
      }

      tx.update(userRef, {
        streakCount: nextStreak,
        lastPlayedDate: date,
      });
    });

    logger.info('Updated streak', { drawerId, date });
  },
);
