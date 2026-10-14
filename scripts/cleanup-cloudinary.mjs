// يحذف من Cloudinary الملفات اليتيمة: ملفات لا يشير إليها أي منشور في Firestore
// (منشورات محذوفة، أو قصص انتهت مدتها). يعمل من GitHub Actions.
//
// الأسرار المطلوبة (متغيرات بيئة):
//   CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
//   FIREBASE_SERVICE_ACCOUNT  (نص JSON لحساب الخدمة)
// اختيارية:
//   DRY_RUN=false   حذف فعلي (الافتراضي: تجربة فقط، لا يحذف شيئاً)
//   FORCE=true      يتجاوز صمامات الأمان (لا تستعمله إلا وأنت متأكد)

import { pathToFileURL } from 'node:url';

const GRACE_HOURS = 24; // لا نحذف ملفاً أحدث من هذا (قد يكون منشوره قيد الإنشاء)
const STORY_HOURS = 24; // عمر القصة
const BATCH = 100; // أقصى عدد ملفات في طلب حذف واحد
// الصور التجريبية التي تضعها Cloudinary في أي حساب جديد: نتجاهلها ولا نحذفها.
const DEMO_ASSET = /^(samples\/|sample$|cld-sample(-\d+)?$|main-sample$)/;

/** يستخرج النوع والمعرّف العام من رابط Cloudinary، أو null إن لم يُفهم الرابط. */
export function parseCloudinaryUrl(url) {
  if (typeof url !== 'string') return null;
  const m = /^https:\/\/res\.cloudinary\.com\/[^/]+\/(image|video)\/upload\/(?:v\d+\/)?(.+?)(?:\.[A-Za-z0-9]+)?$/.exec(
    url
  );
  if (!m) return null;
  const publicId = decodeURIComponent(m[2]);
  // رابط فيه تحويلات (مثل f_auto,q_auto) لا نثق بتفسيره.
  if (publicId.includes(',')) return null;
  return { type: m[1], publicId };
}

/** يحدد اليتامى: ملفات غير مشار إليها وأقدم من فترة السماح. */
export function findOrphans(assets, referenced, now, graceHours = GRACE_HOURS) {
  const cutoff = now - graceHours * 3600 * 1000;
  return assets.filter(
    (a) =>
      !DEMO_ASSET.test(a.publicId) &&
      !referenced.has(`${a.type}:${a.publicId}`) &&
      new Date(a.createdAt).getTime() < cutoff
  );
}

/** صمامات الأمان: ترجع نص المشكلة أو null إن كان كل شيء سليماً. */
export function safetyProblem({ assets, orphans, referencedCount, unparseable }) {
  if (unparseable > 0) {
    return `يوجد ${unparseable} رابط Cloudinary لم أستطع فهمه، فتوقفت حتى لا أحذف ملفاً مستعملاً.`;
  }
  if (assets.length > 0 && referencedCount === 0) {
    return 'لم أجد أي منشور يشير إلى Cloudinary بينما توجد ملفات، فربما القراءة من Firestore فشلت. توقفت.';
  }
  if (assets.length >= 20 && orphans.length / assets.length > 0.5) {
    return `سأحذف ${orphans.length} من ${assets.length} ملفاً (أكثر من النصف)، وهذا غير معتاد. توقفت.`;
  }
  return null;
}

async function main() {
  const env = process.env;
  for (const k of [
    'CLOUDINARY_CLOUD_NAME',
    'CLOUDINARY_API_KEY',
    'CLOUDINARY_API_SECRET',
    'FIREBASE_SERVICE_ACCOUNT',
  ]) {
    if (!env[k]) {
      console.error(`المتغير ${k} غير موجود. أضفه في أسرار GitHub.`);
      process.exit(1);
    }
  }
  const dryRun = env.DRY_RUN !== 'false';
  const force = env.FORCE === 'true';
  const cloud = env.CLOUDINARY_CLOUD_NAME;
  const auth =
    'Basic ' +
    Buffer.from(`${env.CLOUDINARY_API_KEY}:${env.CLOUDINARY_API_SECRET}`).toString('base64');

  async function api(path, method = 'GET') {
    const res = await fetch(`https://api.cloudinary.com/v1_1/${cloud}${path}`, {
      method,
      headers: { Authorization: auth },
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`Cloudinary ${res.status}: ${text.slice(0, 300)}`);
    return JSON.parse(text);
  }

  console.log(dryRun ? '== تجربة فقط: لن يُحذف شيء ==' : '== حذف فعلي ==');

  // ---- Firestore ----
  const { initializeApp, cert } = await import('firebase-admin/app');
  const { getFirestore, Timestamp } = await import('firebase-admin/firestore');
  initializeApp({ credential: cert(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT)) });
  const db = getFirestore();
  const now = Date.now();

  // 1) القصص المنتهية (أقدم من 24 ساعة): تُحذف مستنداتها (وتصبح ملفاتها يتيمة).
  const storyCutoff = Timestamp.fromMillis(now - STORY_HOURS * 3600 * 1000);
  const expired = await db
    .collection('posts')
    .where('type', '==', 'story')
    .where('createdAt', '<', storyCutoff)
    .orderBy('createdAt', 'desc')
    .select('mediaUrl')
    .get();
  const expiredIds = new Set(expired.docs.map((d) => d.id));
  console.log(`قصص منتهية: ${expiredIds.size}`);
  if (!dryRun) {
    for (const d of expired.docs) await db.recursiveDelete(d.ref);
  }

  // 2) كل الملفات التي ما زالت منشورات تشير إليها.
  const referenced = new Set();
  let unparseable = 0;
  const posts = await db.collection('posts').select('mediaUrl').get();
  for (const d of posts.docs) {
    if (expiredIds.has(d.id)) continue;
    const url = d.get('mediaUrl');
    if (typeof url !== 'string' || !url.startsWith('https://res.cloudinary.com/')) continue;
    const p = parseCloudinaryUrl(url);
    if (!p) unparseable++;
    else referenced.add(`${p.type}:${p.publicId}`);
  }
  console.log(`ملفات مشار إليها: ${referenced.size}`);

  // ---- Cloudinary ----
  const assets = [];
  for (const type of ['image', 'video']) {
    let cursor = '';
    do {
      const q = `?max_results=500${cursor ? `&next_cursor=${encodeURIComponent(cursor)}` : ''}`;
      const page = await api(`/resources/${type}/upload${q}`);
      for (const r of page.resources || []) {
        assets.push({ type, publicId: r.public_id, createdAt: r.created_at, bytes: r.bytes || 0 });
      }
      cursor = page.next_cursor || '';
    } while (cursor);
  }
  console.log(`ملفات في Cloudinary: ${assets.length}`);

  const orphans = findOrphans(assets, referenced, now);
  const mb = (orphans.reduce((s, a) => s + a.bytes, 0) / 1048576).toFixed(1);
  console.log(`ملفات يتيمة: ${orphans.length} (حوالي ${mb}MB)`);
  for (const a of orphans.slice(0, 50)) console.log(`  - ${a.type}/${a.publicId}`);

  const problem = safetyProblem({
    assets,
    orphans,
    referencedCount: referenced.size,
    unparseable,
  });
  if (problem && !force) {
    console.error(`!! ${problem}`);
    process.exit(1);
  }
  if (dryRun) {
    console.log('تجربة فقط: انتهت دون حذف.');
    return;
  }

  for (const type of ['image', 'video']) {
    const ids = orphans.filter((a) => a.type === type).map((a) => a.publicId);
    for (let i = 0; i < ids.length; i += BATCH) {
      const params = new URLSearchParams();
      for (const id of ids.slice(i, i + BATCH)) params.append('public_ids[]', id);
      params.set('invalidate', 'true');
      await api(`/resources/${type}/upload?${params}`, 'DELETE');
      console.log(`حُذفت دفعة ${type}: ${Math.min(BATCH, ids.length - i)}`);
    }
  }
  console.log('اكتمل الحذف.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
