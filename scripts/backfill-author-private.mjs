// يضبط الحقل authorPrivate على كل منشور (وقصة) حسب إعداد isPrivate لصاحبه.
// ضروري مرة واحدة قبل نشر قواعد الخصوصية الجديدة: الاستعلامات العامة صارت تشترط
// authorPrivate == false، فالمنشورات القديمة التي لا تحمل الحقل لن تظهر في الرئيسية.
// آمن لإعادة التشغيل (يعدّل ما يخالف الإعداد الحالي فقط)، ويصلح أيضاً أي منشورات خرجت عن التزامن.
//
// المتغيرات (أسرار GitHub):
//   FIREBASE_SERVICE_ACCOUNT  نص JSON لحساب الخدمة
// اختياري:
//   DRY_RUN=false   تعديل فعلي (الافتراضي: تجربة فقط، لا يعدّل شيئاً)

const PAGE = 500;

async function main() {
  const env = process.env;
  if (!env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('المتغير FIREBASE_SERVICE_ACCOUNT غير موجود. أضفه في أسرار GitHub.');
    process.exit(1);
  }
  const dryRun = env.DRY_RUN !== 'false';
  console.log(dryRun ? '== تجربة فقط: لن يُعدَّل شيء ==' : '== تعديل فعلي ==');

  const { initializeApp, cert } = await import('firebase-admin/app');
  const { getFirestore, FieldPath } = await import('firebase-admin/firestore');
  initializeApp({ credential: cert(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT)) });
  const db = getFirestore();

  // 1) من هم أصحاب الحسابات الخاصة؟
  const users = await db.collection('users').select('isPrivate').get();
  const privateUids = new Set();
  for (const u of users.docs) if (u.get('isPrivate') === true) privateUids.add(u.id);
  console.log(`مستخدمون: ${users.size} (خاص: ${privateUids.size})`);

  // 2) صمام أمان: لا نكمل إن لم نقرأ أي مستخدم بينما توجد منشورات (قد تكون القراءة فشلت).
  const anyPost = await db.collection('posts').limit(1).get();
  if (users.empty && !anyPost.empty) {
    console.error('لم أجد أي مستخدم بينما توجد منشورات؛ ربما فشلت القراءة. توقفت.');
    process.exit(1);
  }

  // 3) نمرّ على كل المنشورات صفحة بصفحة ونعدّل المخالف.
  const writer = db.bulkWriter();
  let scanned = 0;
  let toFix = 0;
  let toPrivate = 0;
  let toPublic = 0;
  let last = null;

  for (;;) {
    let q = db
      .collection('posts')
      .orderBy(FieldPath.documentId())
      .select('uid', 'authorPrivate')
      .limit(PAGE);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;

    for (const d of page.docs) {
      scanned++;
      const want = privateUids.has(d.get('uid'));
      if (d.get('authorPrivate') === want) continue;
      toFix++;
      want ? toPrivate++ : toPublic++;
      if (!dryRun) writer.update(d.ref, { authorPrivate: want });
    }
    last = page.docs[page.docs.length - 1];
  }

  if (!dryRun) await writer.close();
  console.log(`منشورات ممسوحة: ${scanned}`);
  console.log(`تحتاج تعديلاً: ${toFix} (إلى خاص: ${toPrivate}، إلى عام: ${toPublic})`);
  console.log(dryRun ? 'لم يُعدَّل شيء (تجربة).' : 'تم التعديل.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
