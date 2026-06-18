import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { dailyWordReset } from './dailyReset';
export { addFriendByCode } from './friendInvite';
export { getGuessHint } from './getGuessHint';
export { onDrawingSubmitted, onGuessCorrect } from './notifications';
export { onDrawingStreak } from './streak';
export { submitGuess } from './submitGuess';
