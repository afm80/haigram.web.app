const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const { defineSecret } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentDeleted,
} = require('firebase-functions/v2/firestore');

initializeApp();

const ADMIN_UID = '7M8bvw0UUiR8Ouxx28nq4i4spQF3';
const CLOUDINARY_CLOUD_NAME = defineSecret('CLOUDINARY_CLOUD_NAME');
const CLOUDINARY_API_KEY = defineSecret('CLOUDINARY_API_KEY');
const CLOUDINARY_API_SECRET = defineSecret('CLOUDINARY_API_SECRET');

function requireAdmin(request) {
  if (request.auth?.uid !== ADMIN_UID) {
    throw new HttpsError('permission-denied', 'غير مصرح بتنفيذ هذا الإجراء.');
  }
}

async function deleteCloudinaryAsset(url) {
  if (typeof url !== 'string') return;
  const parsed = new URL(url);
  if (parsed.hostname !== 'res.cloudinary.com') return;

  const parts = parsed.pathname.split('/').filter(Boolean);
  const uploadIndex = parts.indexOf('upload');
  if (uploadIndex < 0 || !parts[uploadIndex + 1]) return;
  const cloudName = parts[0];
  if (cloudName !== CLOUDINARY_CLOUD_NAME.value()) return;

  let publicIdParts = parts.slice(uploadIndex + 1);
  if (/^v\d+$/.test(publicIdParts[0] || '')) publicIdParts = publicIdParts.slice(1);
  const last = publicIdParts.at(-1) || '';
  publicIdParts[publicIdParts.length - 1] = last.replace(/\.[^.]+$/, '');
  const publicId = publicIdParts.join('/');
  if (!publicId) return;

  const timestamp = Math.floor(Date.now() / 1000);
  const crypto = require('node:crypto');
  const signature = crypto
    .createHash('sha1')
    .update(`public_id=${publicId}&timestamp=${timestamp}${CLOUDINARY_API_SECRET.value()}`)
    .digest('hex');
  const body = new URLSearchParams({
    public_id: publicId,
    timestamp: String(timestamp),
    api_key: CLOUDINARY_API_KEY.value(),
    signature,
  });
  const response = await fetch(
    `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/destroy`,
    { method: 'POST', body },
  );
  const result = await response.json();
  if (!response.ok || !['ok', 'not found'].includes(result.result)) {
    throw new Error(`Cloudinary deletion failed: ${result.result || response.status}`);
  }
}

async function isCloudinaryUrlUsedElsewhere(db, url, excludePostId) {
  const posts = db.collection('posts');
  const [asCover, asAlbum] = await Promise.all([
    posts.where('mediaUrl', '==', url).limit(2).get(),
    posts.where('albumUrls', 'array-contains', url).limit(2).get(),
  ]);
  return [...asCover.docs, ...asAlbum.docs].some((doc) => doc.id !== excludePostId);
}

async function deletePostRecord(db, bucket, postId) {
  const postRef = db.collection('posts').doc(postId);
  const snapshot = await postRef.get();
  if (!snapshot.exists) return false;

  const post = snapshot.data();
  if (typeof post.mediaId === 'string' && post.mediaId && post.repostedFromPostId == null) {
    // حقول المنشور يكتبها العميل، فلا نثق بها: نحذف القطعة فقط إذا كان
    // uid المسجَّل عليها هو صاحب المنشور، حتى لا يُستعمل منشور مزيَّف لحذف ملفات غيره.
    const chunks = Math.max(0, Math.min(Number(post.chunks) || 0, 10000));
    for (let start = 0; start < chunks; start += 400) {
      const refs = [];
      for (let index = start; index < Math.min(start + 400, chunks); index++) {
        refs.push(db.collection('media').doc(`${post.mediaId}_${index}`));
      }
      const docs = await db.getAll(...refs);
      const batch = db.batch();
      let owned = 0;
      docs.forEach((doc) => {
        if (doc.exists && doc.get('uid') === post.uid) {
          batch.delete(doc.ref);
          owned++;
        }
      });
      if (owned > 0) await batch.commit();
    }
  }

  const mediaUrls = [post.mediaUrl, ...(Array.isArray(post.albumUrls) ? post.albumUrls : [])];
  for (const url of mediaUrls) {
    if (typeof url !== 'string') continue;
    if (url.startsWith('https://res.cloudinary.com/')) {
      // أفضل جهد: فشل Cloudinary لا يوقف حذف المنشور أو الحساب؛
      // السكربت الأسبوعي cleanup-cloudinary يحذف ما يتبقى.
      try {
        // رابط Cloudinary لا يحمل مالكه (الرفع غير موقّع)، فلا نحذف الأصل إن كان
        // منشور آخر يشير إليه (إعادة نشر، أو منشور مزيَّف نسخ رابط غيره).
        if (await isCloudinaryUrlUsedElsewhere(db, url, postId)) continue;
        await deleteCloudinaryAsset(url);
      } catch (error) {
        console.error('Cloudinary asset deletion skipped:', url, error);
      }
      continue;
    }
    try {
      const parsed = new URL(url);
      if (parsed.hostname !== 'firebasestorage.googleapis.com') continue;
      const match = parsed.pathname.match(/\/o\/(.+)$/);
      if (!match) continue;
      const objectPath = decodeURIComponent(match[1]);
      if (objectPath.startsWith(`photos/${post.uid}/`)) {
        await bucket.file(objectPath).delete({ ignoreNotFound: true });
      }
    } catch (error) {
      if (error.code !== 404) throw error;
    }
  }

  await db.recursiveDelete(postRef);
  if (typeof post.uid === 'string') {
    await db.collection('users').doc(post.uid).update({
      pinnedPostIds: FieldValue.arrayRemove(postId),
    }).catch(() => {});
  }
  return true;
}

async function deleteRefsInBatches(db, refs) {
  for (let start = 0; start < refs.length; start += 400) {
    const batch = db.batch();
    refs.slice(start, start + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

async function deleteUserComments(db, uid) {
  const comments = await db.collectionGroup('comments').where('uid', '==', uid).get();
  const byPost = new Map();
  for (const comment of comments.docs) {
    const postRef = comment.ref.parent.parent;
    if (!postRef) continue;
    const postId = postRef.id;
    const entry = byPost.get(postId) || { postRef, commentIds: new Set(), refs: new Map() };
    entry.commentIds.add(comment.id);
    entry.refs.set(comment.ref.path, comment.ref);
    byPost.set(postId, entry);
  }

  for (const { postRef, commentIds, refs } of byPost.values()) {
    for (const commentId of commentIds) {
      const replies = await postRef.collection('comments').where('parentId', '==', commentId).get();
      replies.docs.forEach((reply) => refs.set(reply.ref.path, reply.ref));
    }

    await deleteRefsInBatches(db, [...refs.values()]);
    const post = await postRef.get();
    if (post.exists) {
      const current = Math.max(0, Number(post.data().comments) || 0);
      await postRef.update({ comments: Math.max(0, current - refs.size) });
    }
  }
}

async function deleteUserLikes(db, userRef, uid) {
  const likes = await userRef.collection('liked').get();
  for (let start = 0; start < likes.docs.length; start += 200) {
    const page = likes.docs.slice(start, start + 200);
    const entries = await Promise.all(page.map(async (likedPost) => {
      const postRef = db.collection('posts').doc(likedPost.id);
      const likeRef = postRef.collection('likes').doc(uid);
      const [post, like] = await Promise.all([postRef.get(), likeRef.get()]);
      return { postRef, likeRef, post, like };
    }));
    const batch = db.batch();
    let writes = 0;
    for (const entry of entries) {
      if (!entry.like.exists) continue;
      batch.delete(entry.likeRef);
      writes++;
      if (entry.post.exists) {
        batch.update(entry.postRef, {
          likes: Math.max(0, (Number(entry.post.data().likes) || 0) - 1),
        });
        writes++;
      }
    }
    if (writes) await batch.commit();
  }

  const commentLikes = await db.collectionGroup('comments')
    .where('likedBy', 'array-contains', uid)
    .get();
  for (let start = 0; start < commentLikes.docs.length; start += 400) {
    const batch = db.batch();
    commentLikes.docs.slice(start, start + 400).forEach((comment) => {
      batch.update(comment.ref, { likedBy: FieldValue.arrayRemove(uid) });
    });
    await batch.commit();
  }
}

async function deleteActorNotifications(db, uid) {
  const notifications = await db.collectionGroup('notifications')
    .where('actorUid', '==', uid)
    .get();
  await deleteRefsInBatches(db, notifications.docs.map((item) => item.ref));
}

exports.adminDeletePost = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 300,
    secrets: [CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
  },
  async (request) => {
    requireAdmin(request);
    const postId = request.data?.postId;
    if (typeof postId !== 'string' || !postId || postId.length > 1500) {
      throw new HttpsError('invalid-argument', 'معرّف المنشور غير صالح.');
    }

    try {
      const deleted = await deletePostRecord(
        getFirestore(),
        getStorage().bucket(),
        postId,
      );
      return { deleted };
    } catch (error) {
      console.error('Admin post deletion failed:', postId, error);
      throw new HttpsError('internal', 'تعذر حذف المنشور ومحتوياته.');
    }
  },
);

async function deleteUserAccount(uid) {
    const db = getFirestore();
    const bucket = getStorage().bucket();
    const userRef = db.collection('users').doc(uid);

    try {
      const userSnapshot = await userRef.get();
      const username = userSnapshot.data()?.username;

      const [posts, chats, following, followers] = await Promise.all([
        db.collection('posts').where('uid', '==', uid).get(),
        db.collection('chats').where('participants', 'array-contains', uid).get(),
        userRef.collection('following').get(),
        userRef.collection('followers').get(),
      ]);

      await deleteUserComments(db, uid);
      await deleteUserLikes(db, userRef, uid);
      await deleteActorNotifications(db, uid);

      for (const post of posts.docs) {
        await deletePostRecord(db, bucket, post.id);
      }

      const relationshipRefs = [
        ...following.docs.map((item) =>
          db.collection('users').doc(item.id).collection('followers').doc(uid)),
        ...followers.docs.map((item) =>
          db.collection('users').doc(item.id).collection('following').doc(uid)),
      ];
      await deleteRefsInBatches(db, relationshipRefs);

      for (const chat of chats.docs) {
        await bucket.deleteFiles({ prefix: `chats/${chat.id}/` });
        await db.recursiveDelete(chat.ref);
      }

      await bucket.deleteFiles({ prefix: `photos/${uid}/` });
      // أرشيف القصص والمميزة ومشاهداتها: بيانات الحساب تُحذف معه
      // (ملفات Cloudinary اليتيمة ينظفها السكربت الأسبوعي).
      for (const col of ['storyArchive', 'storyHighlights', 'storySeen']) {
        await db.recursiveDelete(db.collection(col).doc(uid)).catch((error) => {
          console.error('Story data deletion skipped:', col, uid, error);
        });
      }
      if (typeof username === 'string' && username) {
        const usernameRef = db.collection('usernames').doc(username);
        const usernameSnapshot = await usernameRef.get();
        if (usernameSnapshot.data()?.uid === uid) await usernameRef.delete();
      }

      // Remove the sign-in first so the account cannot continue writing while cleanup runs.
      await getAuth().deleteUser(uid).catch((error) => {
        if (error.code !== 'auth/user-not-found') throw error;
      });
      await db.recursiveDelete(userRef);
      return { deleted: true };
    } catch (error) {
      console.error('User deletion failed:', uid, error);
      throw new HttpsError('internal', 'تعذر حذف الحساب وكل بياناته.');
    }
}

exports.adminDeleteUser = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '1GiB',
    secrets: [CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
  },
  async (request) => {
    requireAdmin(request);
    const uid = request.data?.uid;
    if (typeof uid !== 'string' || !uid || uid.length > 128) {
      throw new HttpsError('invalid-argument', 'معرّف المستخدم غير صالح.');
    }
    if (uid === ADMIN_UID) {
      throw new HttpsError('failed-precondition', 'لا يمكن حذف حساب الأدمن.');
    }

    return await deleteUserAccount(uid);
  },
);

exports.deleteMyAccount = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '1GiB',
    secrets: [CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً.');
    }
    if (uid === ADMIN_UID) {
      throw new HttpsError('failed-precondition', 'لا يمكن حذف حساب الأدمن.');
    }
    return await deleteUserAccount(uid);
  },
);

exports.adminSetUserBlocked = onCall(
  { region: 'us-central1' },
  async (request) => {
    requireAdmin(request);
    const uid = request.data?.uid;
    const blocked = request.data?.blocked;
    if (typeof uid !== 'string' || !uid || uid.length > 128 || typeof blocked !== 'boolean') {
      throw new HttpsError('invalid-argument', 'بيانات الحظر غير صالحة.');
    }
    if (uid === ADMIN_UID) {
      throw new HttpsError('failed-precondition', 'لا يمكن حظر حساب الأدمن.');
    }

    const db = getFirestore();
    const auth = getAuth();
    const blockRef = db.collection('blockedUsers').doc(uid);
    try {
      const currentBlock = await blockRef.get();
      if (blocked) {
        const account = await auth.getUser(uid);
        if (!currentBlock.exists) {
          await blockRef.create({
            uid,
            blockedBy: request.auth.uid,
            blockedAt: FieldValue.serverTimestamp(),
            disabledBeforeBlock: account.disabled === true,
          });
        }
        await db.collection('presence').doc(uid).set({
          online: false,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        await auth.updateUser(uid, { disabled: true });
        await auth.revokeRefreshTokens(uid);
        return { blocked: true };
      }

      if (!currentBlock.exists) return { blocked: false };
      const disabledBeforeBlock = currentBlock.data()?.disabledBeforeBlock === true;
      await auth.updateUser(uid, { disabled: disabledBeforeBlock });
      await auth.revokeRefreshTokens(uid);
      await blockRef.delete();
      return { blocked: false };
    } catch (error) {
      console.error('Admin account block update failed:', uid, error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'تعذر تحديث حالة حظر الحساب.');
    }
  },
);

// نص الإشعار بحسب نوع الرسالة (بدل عرض النص الخام لكل الأنواع).
function chatNotificationBody(message) {
  switch (message.kind) {
    case 'image':
      return '📷 صورة جديدة';
    case 'audio':
      return '🎤 رسالة صوتية';
    case 'gif':
      return '🎞 GIF';
    case 'location':
      return '📍 موقع';
    case 'share':
      return '🔗 مشاركة';
    case 'sticker':
      return String(message.text || '🙂').slice(0, 40);
    default:
      return String(message.text || 'رسالة جديدة').slice(0, 160);
  }
}

// الكتم: دائم (muted = true) أو مؤقت (mutedUntil لم ينتهِ بعد).
function isChatMutedFor(chat, uid, nowMs) {
  if (chat?.muted?.[uid] === true) return true;
  const until = chat?.mutedUntil?.[uid];
  const untilMs = typeof until?.toMillis === 'function' ? until.toMillis() : 0;
  return untilMs > nowMs;
}

exports.notifyChatMessage = onDocumentCreated(
  {
    document: 'chats/{chatId}/messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const message = event.data?.data();
    if (!message || typeof message.senderUid !== 'string') return;
    // أثر «تم حذف الرسالة» لا يُشعِر أحداً.
    if (message.kind === 'deleted') return;

    const db = getFirestore();
    const chatSnapshot = await db.doc(`chats/${event.params.chatId}`).get();
    const chat = chatSnapshot.data();
    const participants = chat?.participants;
    if (!Array.isArray(participants) || participants.length < 2) return;

    // محادثة فردية أو مجموعة: كل الأعضاء ما عدا المرسل، بعد استثناء من كتم.
    const nowMs = Date.now();
    const recipients = participants.filter(
      (uid) =>
        typeof uid === 'string' &&
        uid !== message.senderUid &&
        !isChatMutedFor(chat, uid, nowMs),
    );
    if (recipients.length === 0) return;

    const tokenRefs = [];
    const tokens = [];
    await Promise.all(
      recipients.map(async (uid) => {
        const snapshot = await db
          .collection('users')
          .doc(uid)
          .collection('pushTokens')
          .get();
        snapshot.docs.forEach((doc) => {
          const token = doc.data().token;
          if (typeof token === 'string' && token) {
            tokens.push(token);
            tokenRefs.push(doc.ref);
          }
        });
      }),
    );
    if (tokens.length === 0) return;

    const senderSnapshot = await db.doc(`users/${message.senderUid}`).get();
    const senderName = String(
      senderSnapshot.data()?.name ||
        senderSnapshot.data()?.username ||
        'Haigram',
    );
    const isGroup = chat?.isGroup === true;
    // المجموعة: عنوان الإشعار اسمها، والمرسل يسبق النص.
    const title = isGroup ? String(chat?.groupName || 'Haigram') : senderName;
    const content = chatNotificationBody(message);
    const body = isGroup ? `${senderName}: ${content}` : content;

    const payload = {
      // بلا حقل notification على مستوى الرسالة: على الويب يعرض الـ service worker
      // الإشعار بنفسه (وإلا ظهر إشعاران: تلقائي + يدوي). أندرويد يعرضه من
      // android.notification.
      data: {
        type: 'chat',
        title,
        body,
        tag: `chat_${event.params.chatId}`,
        conversationId: event.params.chatId,
        messageId: event.params.messageId,
        senderUid: message.senderUid,
      },
      webpush: { headers: { Urgency: 'high' } },
      android: {
        priority: 'high',
        notification: { title, body, tag: `chat_${event.params.chatId}` },
      },
    };

    // حد FCM: 500 توكن في الطلب الواحد (المجموعة قد تصل إلى 250 عضواً).
    const staleTokens = [];
    for (let start = 0; start < tokens.length; start += 500) {
      const chunk = tokens.slice(start, start + 500);
      const response = await getMessaging().sendEachForMulticast({
        ...payload,
        tokens: chunk,
      });
      response.responses.forEach((result, index) => {
        if (
          !result.success &&
          ['messaging/invalid-registration-token',
            'messaging/registration-token-not-registered'].includes(
              result.error?.code,
            )
        ) {
          staleTokens.push(tokenRefs[start + index]);
        }
      });
    }
    if (staleTokens.length > 0) {
      const batch = db.batch();
      staleTokens.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
  },
);


// إشعارات النشاط (إعجاب، تعليق، متابعة...) على الجهاز مثل إنستغرام.
// كل إشعار جديد في users/{uid}/notifications يُرسَل كإشعار دفع لأجهزة صاحبه.
exports.notifyActivity = onDocumentCreated(
  {
    document: 'users/{uid}/notifications/{notificationId}',
    region: 'us-central1',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data || typeof data.type !== 'string') return;

    const actor = String(data.actorUsername || 'مستخدم');
    let body;
    let groupTag;
    switch (data.type) {
      case 'like': {
        // تجميع الإعجابات مثل إنستغرام: إشعار واحد لكل منشور يتحدّث نصه
        // («فلان و3 آخرون أعجبوا بمنشورك») بدل إشعار منفصل لكل إعجاب.
        groupTag = `like_${data.postId || ''}`;
        let others = 0;
        try {
          const likes = await getFirestore()
            .collection('users')
            .doc(event.params.uid)
            .collection('notifications')
            .where('type', '==', 'like')
            .where('postId', '==', data.postId || '')
            .count()
            .get();
          others = Math.max(0, likes.data().count - 1);
        } catch (error) {
          console.error('Like count failed:', error);
        }
        body = others > 0
          ? `و${others} آخرون أعجبوا بمنشورك`
          : 'أعجب بمنشورك';
        break;
      }
      case 'comment':
        body = `علّق: ${String(data.commentText || '').slice(0, 100)}`;
        break;
      case 'follow':
        body = 'بدأ بمتابعتك';
        break;
      case 'followRequest':
        body = 'طلب متابعتك';
        break;
      case 'followAccepted':
        body = 'قبل طلب متابعتك';
        break;
      default:
        return;
    }

    const db = getFirestore();
    const uid = event.params.uid;
    const tokenSnapshot = await db
      .collection('users')
      .doc(uid)
      .collection('pushTokens')
      .get();
    if (tokenSnapshot.empty) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens: tokenSnapshot.docs.map((doc) => doc.data().token),
      // بيانات فقط (انظر notifyChatMessage): الـ service worker يعرض إشعار الويب.
      data: {
        type: String(data.type),
        title: actor,
        body,
        tag: groupTag || '',
        actorUid: String(data.actorUid || ''),
        postId: String(data.postId || ''),
      },
      webpush: { headers: { Urgency: 'high' } },
      android: {
        priority: 'high',
        // نفس الوسم يستبدل الإشعار السابق بدل تكديس إشعارات جديدة.
        notification: { title: actor, body, ...(groupTag ? { tag: groupTag } : {}) },
      },
    });

    const stale = [];
    response.responses.forEach((result, index) => {
      if (
        !result.success &&
        ['messaging/invalid-registration-token',
          'messaging/registration-token-not-registered'].includes(
            result.error?.code,
          )
      ) {
        stale.push(tokenSnapshot.docs[index].ref);
      }
    });
    if (stale.length > 0) {
      const batch = db.batch();
      stale.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
  },
);

// عند حذف قصة (يدوياً أو بسياسة TTL عند انتهائها) تُحذف مجموعاتها الفرعية
// (views / votes / likes) كي لا تبقى يتيمة وتستهلك الحصة المجانية.
async function purgeStoryChildren(event) {
  const snap = event.data;
  if (!snap || snap.data()?.type !== 'story') return;
  try {
    await getFirestore().recursiveDelete(snap.ref);
  } catch (err) {
    console.error('purgeStoryChildren failed', snap.ref.path, err);
  }
}

exports.cleanupStoryChildren = onDocumentDeleted(
  { document: 'posts/{postId}', region: 'us-central1' },
  purgeStoryChildren,
);

exports.cleanupCloseStoryChildren = onDocumentDeleted(
  { document: 'closeStories/{storyId}', region: 'us-central1' },
  purgeStoryChildren,
);
