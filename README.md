# لمحة (Lamha) — تطبيق فيديوهات قصيرة PWA

Flutter Web + Firebase (Auth / Firestore / Storage / Hosting) — تصميم أصلي بخلفية داكنة، قابل للتثبيت على الآيفون والأندرويد.

## الخطوات للحصول على رابط تجربه من هاتفك

### 1) أنشئ مشروع Firebase (مجاني)
1. ادخل https://console.firebase.google.com ← **Add project**.
2. من **Build → Authentication → Get started** فعّل **Email/Password** و **Google**.
3. من **Build → Firestore Database → Create database** (Production mode).
(لا تحتاج Storage في وضع التجربة المجاني.)
5. من **Project settings → General → Your apps → Web (</>)** سجّل تطبيق ويب، وانسخ القيم (apiKey, appId, messagingSenderId, projectId, authDomain, storageBucket).

> **وضع التجربة المجاني:** الفيديو والصور تُحفظ داخل Firestore (بدون Storage وبدون بطاقة). الحدود: فيديو حتى 60 ثانية و15MB، وصورة حتى 3MB، والحصة الكلية 1GB. للانتقال لاحقاً إلى Firebase Storage (خطة Blaze) أضف `--dart-define=USE_STORAGE=true` في ملف النشر.

### 2) ارفع المشروع إلى GitHub
أنشئ مستودعاً جديداً، ثم من مجلد المشروع:
```bash
git init && git add . && git commit -m "init"
git branch -M main
git remote add origin https://github.com/USERNAME/lamha.git
git push -u origin main
```

### 3) أضف الأسرار في GitHub
**Settings → Secrets and variables → Actions → New repository secret**:

| الاسم | القيمة |
|---|---|
| `FB_API_KEY` | apiKey |
| `FB_APP_ID` | appId |
| `FB_SENDER_ID` | messagingSenderId |
| `FB_PROJECT_ID` | projectId |
| `FB_AUTH_DOMAIN` | authDomain |
| `FB_STORAGE_BUCKET` | storageBucket |
| `FIREBASE_SERVICE_ACCOUNT` | محتوى ملف JSON لحساب الخدمة (Project settings → Service accounts → Generate new private key) |

### 4) انشر قواعد الأمان والفهارس (مرة واحدة)
```bash
npm i -g firebase-tools
firebase login
firebase use YOUR_PROJECT_ID
firebase deploy --only firestore
```

### 5) شغّل النشر
أي `push` على `main` يبني التطبيق وينشره تلقائياً (أو من تبويب **Actions** اضغط Run workflow).
الرابط: `https://YOUR_PROJECT_ID.web.app` — افتحه من هاتفك.

### 6) التثبيت على الهاتف
- **أندرويد (Chrome):** ستظهر نافذة "تثبيت" تلقائياً.
- **آيفون (Safari):** زر المشاركة ← **إضافة إلى الشاشة الرئيسية**.

## تشغيل محلي
```bash
flutter create . --platforms=web   # مرة واحدة
flutter pub get
flutter run -d chrome \
  --dart-define=FB_API_KEY=... --dart-define=FB_APP_ID=... \
  --dart-define=FB_SENDER_ID=... --dart-define=FB_PROJECT_ID=... \
  --dart-define=FB_AUTH_DOMAIN=... --dart-define=FB_STORAGE_BUCKET=...
```

## حدود معروفة
- **قص الفيديو:** الفيديو الأطول من 60 ثانية يُقصّ تلقائياً إلى أول 60 ثانية عبر ffmpeg.wasm (ملفاته في `web/ffmpeg`، ~32MB، تُحمَّل فقط عند الحاجة). القص بدون إعادة ترميز، فهو سريع لكنه لا يصغّر الحجم: يجب أن يبقى الناتج ≤ 40MB وإلا يُطلب تصوير بجودة أقل. الحد الأقصى للملف الأصلي 300MB. الصور تُضغط تلقائياً.
- **التعليقات والمشاركة:** أزرار جاهزة شكلاً، والتعليقات "قريباً".
- لم أستطع تشغيل Flutter في بيئتي، فالكود لم يُترجم فعلياً بعد؛ شغّل `flutter analyze` أولاً وأرسل لي أي خطأ يظهر.
