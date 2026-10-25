// ضغط وقص الفيديو على الأندرويد بمكتبة video_compress (ضاغط الجهاز نفسه).
// الهدف: دقة أقصاها 540p (جودة جيدة وحجم خفيف)، ومدة لا تتجاوز [maxSeconds].
// الضغط يحوّل الفيديو أيضاً إلى mp4 (H.264) فيعمل عند الجميع مهما كانت صيغته.
import 'dart:io';
import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

import '../l10n.dart';
import 'video_prepare_types.dart';

String _tooLongMsg(int s) =>
    trf('تعذّر تقصير الفيديو على هذا الجهاز. اختر فيديو أقصر من {0} ثانية', [s]);

Future<VideoSize?> probeVideoSizeImpl(String path) async {
  final info = await VideoCompress.getMediaInfo(path);
  var w = info.width ?? 0, h = info.height ?? 0;
  if (w == 0 || h == 0) return null;
  // فيديو الجوال المصوَّر عمودياً يُخزَّن أفقياً مع تدوير 90/270.
  final o = info.orientation ?? 0;
  if (o == 90 || o == 270) {
    final t = w;
    w = h;
    h = t;
  }
  return VideoSize(w, h);
}

Future<VideoPoster?> grabVideoPosterImpl(String path) async {
  final size = await probeVideoSizeImpl(path);
  if (size == null) return null;
  final Uint8List? bytes =
      await VideoCompress.getByteThumbnail(path, quality: 80);
  if (bytes == null || bytes.isEmpty) return null;
  return VideoPoster(bytes, size);
}

Future<PreparedVideo?> prepareVideoImpl({
  required String blobUrl,
  required int originalSize,
  required int maxSeconds,
  required int keepOriginalBytes,
  void Function(double progress)? onProgress,
}) async {
  final path = blobUrl; // على الأندرويد هو مسار الملف
  double? dur; // بالثواني
  try {
    final info = await VideoCompress.getMediaInfo(path);
    if (info.duration != null) dur = info.duration! / 1000;
  } catch (_) {}
  final tooLong = dur != null && dur > maxSeconds + 0.5;
  if (!tooLong && originalSize <= keepOriginalBytes) return null;

  Subscription? sub;
  try {
    sub = VideoCompress.compressProgress$.subscribe((p) {
      onProgress?.call((p / 100).clamp(0.0, 1.0));
    });

    // ضغط بدقة 540p، مع قص عند الحاجة. معنى معامل المدة في المكتبة غير موثّق
    // بوضوح (قد يكون «ما يُقصّ من النهاية»)، لذلك نتحقق من طول الناتج فعلياً
    // ونجرّب المعنى الآخر إن لم يطابق.
    Future<MediaInfo?> run(int? trimArg) => VideoCompress.compressVideo(
          path,
          quality: VideoQuality.Res960x540Quality,
          deleteOrigin: false,
          includeAudio: true,
          duration: trimArg,
        );

    MediaInfo? best;
    double bestLen = -1;
    void consider(MediaInfo? m) {
      if (m == null || m.path == null) return;
      final len = (m.duration ?? 0) / 1000;
      if (len <= maxSeconds + 1.5 && len > bestLen) {
        best = m;
        bestLen = len;
      }
    }

    if (!tooLong) {
      consider(await run(null));
    } else {
      final expected = maxSeconds.toDouble();
      // المحاولة 1: المعامل = ثواني تُقصّ من النهاية.
      consider(await run((dur! - maxSeconds).ceil()));
      // المحاولة 2 (فقط إن لم يأتِ الطول قريباً من المطلوب): المعامل = المدة المطلوبة.
      if (bestLen < expected - 5) {
        onProgress?.call(0);
        consider(await run(maxSeconds));
      }
    }

    final out = best;
    if (out == null) {
      if (tooLong) throw StateError(_tooLongMsg(maxSeconds));
      return null;
    }
    // إن لم يصغر الملف (كان خفيفاً أصلاً) نبقي الأصلي بدل خسارة جودة بلا فائدة.
    // (فقط للصيغ التي يقبلها الخادم كما هي.)
    final lower = path.toLowerCase();
    final acceptedAsIs = lower.endsWith('.mp4') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
    if (!tooLong &&
        acceptedAsIs &&
        await File(out.path!).length() >= originalSize) {
      return null;
    }
    final bytes = await File(out.path!).readAsBytes();
    onProgress?.call(1);
    return PreparedVideo(bytes, 'video/mp4');
  } on StateError {
    rethrow;
  } catch (_) {
    if (tooLong) throw StateError(_tooLongMsg(maxSeconds));
    return null;
  } finally {
    try {
      sub?.unsubscribe();
    } catch (_) {}
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }
}
