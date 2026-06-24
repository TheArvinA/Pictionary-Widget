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
  'apple', 'banana', 'carrot', 'guitar', 'piano', 'trumpet',
  'elephant', 'giraffe', 'penguin', 'dolphin', 'butterfly', 'spider',
  'snail', 'turtle', 'rabbit', 'squirrel', 'hedgehog', 'owl',
  'tiger', 'lion', 'zebra', 'monkey', 'panda', 'koala',
  'airplane', 'helicopter', 'rocket', 'tractor', 'bulldozer', 'sailboat',
  'train', 'bus', 'truck', 'scooter', 'motorcycle', 'ambulance',
  'mountain', 'island', 'waterfall', 'desert', 'forest', 'glacier',
  'cactus', 'mushroom', 'sunflower', 'tree', 'leaf', 'acorn',
  'house', 'igloo', 'tent', 'barn', 'bridge', 'tower',
  'clock', 'lamp', 'chair', 'ladder', 'hammer', 'wrench',
  'scissors', 'pencil', 'crayon', 'paintbrush', 'envelope', 'balloon',
  'kite', 'drum', 'flute', 'bell', 'whistle', 'magnet',
  'crown', 'glasses', 'hat', 'boot', 'glove', 'scarf',
  'banjo', 'cello', 'xylophone', 'accordion', 'tambourine', 'trombone',
  'snowman', 'pumpkin', 'cupcake', 'pizza', 'donut', 'pretzel',
  'lemon', 'cherry', 'pineapple', 'strawberry', 'watermelon', 'coconut',
  'starfish', 'seahorse', 'crab', 'lobster', 'shark', 'whale',
  'cloud', 'lightning', 'snowflake', 'moon', 'star', 'planet',
  'camera', 'feather', 'candle', 'mitten', 'rake', 'shovel',
  'broom', 'bucket', 'kettle', 'teapot', 'spoon', 'fork',
];

function todayUtc(): string {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function pickN(words: string[], n: number): string[] {
  const pool = [...words];
  const picked: string[] = [];
  while (picked.length < n && pool.length > 0) {
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

    // Create-once: if the doc for this date already exists (e.g. a manual
    // re-run), skip the rewrite AND the push so the pool isn't reshuffled and
    // users aren't notified twice. The scheduled 00:00 run writes a brand-new
    // date doc that doesn't exist yet, so it still proceeds normally.
    const existing = await db.doc(`daily/${date}`).get();
    if (existing.exists) {
      logger.info('Daily word pool already exists; skipping rewrite and push', { date });
      return;
    }

    // Per-day candidate POOL (not the final 3). Each user picks a random
    // 3-word subset from this pool, persisted to their private round doc, so
    // friends rarely draw the same word.
    const pool = pickN(wordList, 15);

    await db.doc(`daily/${date}`).set({
      wordChoices: pool,
      generatedAt: FieldValue.serverTimestamp(),
    });

    logger.info('Daily word pool written', { date, pool });

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
