// تجهيز الفيديو قبل الرفع: ضغط وقص.
// الويب: داخل المتصفح (MediaRecorder). الأندرويد: مكتبة video_compress الأصلية.
import 'video_prepare_stub.dart'
    if (dart.library.html) 'video_prepare_web.dart'
    if (dart.library.io) 'video_prepare_native.dart' as impl;
import 'video_prepare_types.dart';

export 'video_prepare_types.dart';

/// يعيد null إن لم يلزم تغيير الملف (صغير وقصير) أو لم يُدعم الضغط؛
/// ويرمي StateError برسالة للمستخدم إن تعذّر تقصير فيديو أطول من الحد.
Future<PreparedVideo?> prepareVideo({
  required String blobUrl,
  required int originalSize,
  int maxSeconds = 60,
  int keepOriginalBytes = 40 * 1024 * 1024,
  void Function(double progress)? onProgress,
}) =>
    impl.prepareVideoImpl(
        blobUrl: blobUrl,
        originalSize: originalSize,
        maxSeconds: maxSeconds,
        keepOriginalBytes: keepOriginalBytes,
        onProgress: onProgress);

/// يقرأ أبعاد الفيديو لتحديد قسمه (شورتز أو فيديو عادي). null إن تعذّرت القراءة.
Future<VideoSize?> probeVideoSize(String blobUrl) async {
  try {
    return await impl.probeVideoSizeImpl(blobUrl);
  } catch (_) {
    return null;
  }
}

/// لقطة غلاف وأبعاد الفيديو (لمعاينة القصة). null إن تعذّرت القراءة.
Future<VideoPoster?> grabVideoPoster(String blobUrl) async {
  try {
    return await impl.grabVideoPosterImpl(blobUrl);
  } catch (_) {
    return null;
  }
}
