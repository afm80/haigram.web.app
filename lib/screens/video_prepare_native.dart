// ضغط وقص الفيديو على الأندرويد بمكتبة video_compress (ضاغط الجهاز نفسه).
// الهدف: دقة أقصاها 720p، ومدة لا تتجاوز [maxSeconds].
import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../l10n.dart';
import 'video_prepare_types.dart';

String _tooLongMsg(int s) =>
    trf('تعذّر تقصير الفيديو على هذا الجهاز. اختر فيديو أقصر من {0} ثانية', [s]);

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

    // ضغط بدقة 720p، مع قص عند الحاجة. معنى معامل المدة في المكتبة غير موثّق
    // بوضوح (قد يكون «ما يُقصّ من النهاية»)، لذلك نتحقق من طول الناتج فعلياً
    // ونجرّب المعنى الآخر إن لم يطابق.
    Future<MediaInfo?> run(int? trimArg) => VideoCompress.compressVideo(
          path,
          quality: VideoQuality.Res1280x720Quality,
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
