import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';

const FALLBACK_WORDS = [
  'bicycle', 'volcano', 'saxophone', 'lighthouse', 'octopus', 'telescope',
  'submarine', 'rainbow', 'windmill', 'kangaroo', 'pyramid', 'umbrella',
  'harmonica', 'jellyfish', 'skateboard', 'tornado', 'treehouse', 'violin',
  'campfire', 'compass', 'anchor', 'sandcastle', 'robot', 'spaceship',
  'dragon', 'wizard', 'knight', 'castle', 'unicorn', 'mermaid',
];

function todayUtc(): string {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function pickThree(words: string[]): string[] {
  const pool = [...words];
  const picked: string[] = [];
  while (picked.length < 3 && pool.length > 0) {
    const idx = Math.floor(Math.random() * pool.length);
    picked.push(pool.splice(idx, 1)[0]);
  }
  return picked;
}

export const dailyWordReset = onSchedule(
  {
    schedule: '0 0 * * *',
    timeZone: 'UTC',
    region: 'us-central1',
  },
  async () => {
    const db = getFirestore();
    const masterSnap = await db.doc('wordList/master').get();
    const wordList = (masterSnap.data()?.words as string[] | undefined) ?? FALLBACK_WORDS;

    const date = todayUtc();
    const choices = pickThree(wordList);

    await db.doc(`daily/${date}`).set({
      wordChoices: choices,
      generatedAt: FieldValue.serverTimestamp(),
    });

    logger.info('Daily words written', { date, choices });

    await getMessaging().send({
      topic: 'daily',
      notification: {
        title: "Today's words are ready!",
        body: 'Open Pictionary and start drawing.',
      },
    });

    logger.info('Daily notification sent', { date });
  },
);
