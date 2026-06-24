import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

interface AddFriendData {
  code?: unknown;
}

interface AddFriendResult {
  friendId: string;
  displayName: string;
  alreadyFriends?: boolean;
}

export const addFriendByCode = onCall<AddFriendData, Promise<AddFriendResult>>(
  { region: 'us-central1' },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'You must be signed in.');
    }

    const rawCode = request.data?.code;
    if (typeof rawCode !== 'string') {
      throw new HttpsError('invalid-argument', 'A code is required.');
    }
    const code = rawCode.trim().toUpperCase();
    if (code.length === 0) {
      throw new HttpsError('invalid-argument', 'A code is required.');
    }

    const db = getFirestore();
    const matchSnap = await db
      .collection('users')
      .where('inviteCode', '==', code)
      .limit(1)
      .get();

    if (matchSnap.empty) {
      throw new HttpsError('not-found', 'No user with that code');
    }

    const friendDoc = matchSnap.docs[0];
    const friendId = friendDoc.id;
    const friendData = friendDoc.data();
    const displayName =
      typeof friendData.displayName === 'string' ? friendData.displayName : '';

    if (friendId === callerUid) {
      throw new HttpsError('invalid-argument', "You can't add yourself");
    }

    const existingFriendIds = Array.isArray(friendData.friendIds)
      ? (friendData.friendIds as unknown[])
      : [];
    if (existingFriendIds.includes(callerUid)) {
      return { alreadyFriends: true, friendId, displayName };
    }

    const callerRef = db.doc(`users/${callerUid}`);
    const friendRef = db.doc(`users/${friendId}`);

    const batch = db.batch();
    batch.set(callerRef, { friendIds: FieldValue.arrayUnion(friendId) }, { merge: true });
    batch.set(friendRef, { friendIds: FieldValue.arrayUnion(callerUid) }, { merge: true });
    await batch.commit();

    return { friendId, displayName };
  },
);
