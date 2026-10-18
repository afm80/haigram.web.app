# Haigram

Haigram تطبيق اجتماعي لمشاركة الصور والمنشورات والقصص، واكتشاف المحتوى والتواصل مع الآخرين.

## إشعارات المحادثات

يتطلب نشر إشعارات المحادثات تفعيل Firebase Cloud Messaging، وإنشاء Web Push key من إعدادات المشروع > Cloud Messaging، ثم إضافته في GitHub Actions secrets بالاسم `FB_WEB_PUSH_VAPID_KEY`. يجب أن تكون أسرار Firebase الحالية (`FB_API_KEY` و`FB_APP_ID` و`FB_SENDER_ID` و`FB_PROJECT_ID` و`FB_AUTH_DOMAIN` و`FB_STORAGE_BUCKET`) مضبوطة أيضًا.

ينشر مسار GitHub Actions وظيفة Cloud Function لإرسال الإشعارات. نشر Cloud Functions يتطلب مشروع Firebase على خطة Blaze مع تفعيل الفوترة. لا تُرسل مفاتيح Firebase أو VAPID في المحادثات أو تضعها مباشرة في الشيفرة.

تتطلب دوال حذف المنشورات والحسابات كذلك أسرار Cloudinary في Firebase Secret Manager: `CLOUDINARY_CLOUD_NAME` و`CLOUDINARY_API_KEY` و`CLOUDINARY_API_SECRET`. أضفها قبل نشر الدوال باستخدام `firebase functions:secrets:set` لكل اسم؛ لا تحفظ قيمها في GitHub Actions أو ملفات HTML. إذا لم تُستخدم Cloudinary، يمكن حذف هذه المراجع من الدوال قبل نشرها.
