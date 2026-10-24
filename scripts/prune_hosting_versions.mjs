// يحذف إصدارات Firebase Hosting القديمة لتحرير مساحة التخزين (خطأ 429).
// يُبقي أحدث إصدارات منشورة (KEEP) والإصدار الحي الحالي، ويحذف الباقي.
import crypto from 'node:crypto';

const KEEP = Number(process.env.KEEP_VERSIONS || 3);
const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
const project = process.env.FB_PROJECT_ID || sa.project_id;
const site = process.env.HOSTING_SITE || project;
const API = 'https://firebasehosting.googleapis.com/v1beta1';

if (!sa.private_key || !project) {
  console.log('Missing service account or project id; skipping prune.');
  process.exit(0);
}

const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

async function getToken() {
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    b64({ alg: 'RS256', typ: 'JWT' }) + '.' +
    b64({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/cloud-platform',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    });
  const sig = crypto.createSign('RSA-SHA256').update(unsigned).sign(sa.private_key, 'base64url');
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${sig}`,
    }),
  });
  if (!res.ok) throw new Error(`Token error ${res.status}: ${await res.text()}`);
  return (await res.json()).access_token;
}

async function listAll(token, path, key) {
  const out = [];
  let pageToken = '';
  do {
    const url = `${API}/projects/${project}/sites/${site}/${path}?pageSize=100${pageToken ? `&pageToken=${pageToken}` : ''}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`List ${path} failed ${res.status}: ${await res.text()}`);
    const data = await res.json();
    out.push(...(data[key] || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return out;
}

try {
  const token = await getToken();

  const releases = await listAll(token, 'releases', 'releases');
  const keep = new Set(
    releases.slice(0, KEEP).map((r) => r.version && r.version.name).filter(Boolean),
  );

  const versions = await listAll(token, 'versions', 'versions');
  const victims = versions
    .filter((v) => v.status !== 'DELETED' && !keep.has(v.name))
    .sort((a, b) => new Date(a.createTime) - new Date(b.createTime));

  console.log(`Total versions: ${versions.length}, keeping: ${keep.size}, deleting: ${victims.length}`);

  let deleted = 0;
  for (const v of victims) {
    const res = await fetch(`${API}/${v.name}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.ok) deleted++;
    else console.log(`Skip ${v.name}: ${res.status}`);
  }
  console.log(`Deleted ${deleted} old versions.`);
} catch (e) {
  // لا نوقف النشر بسبب فشل التنظيف
  console.log('Prune failed (non-fatal):', e.message);
}
