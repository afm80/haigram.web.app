// ignore_for_file: avoid_web_libraries_in_flutter
// ضغط وقص الفيديو داخل المتصفح: يُشغَّل الفيديو في الخلفية ويُسجَّل من جديد
// بدقة أقصاها 720p ومعدل بيانات محدود، ولا يتجاوز [maxSeconds].
// التسجيل يجري بسرعة التشغيل الفعلية، فيجب أن تبقى الصفحة مفتوحة.
import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_util' as js_util;

import '../l10n.dart';
import 'video_prepare_types.dart';

const _candidates = [
  'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
  'video/mp4',
  'video/webm;codecs=vp9,opus',
  'video/webm;codecs=vp8,opus',
  'video/webm',
];

String? _pickMime() {
  for (final c in _candidates) {
    try {
      if (html.MediaRecorder.isTypeSupported(c)) return c;
    } catch (_) {}
  }
  return null;
}

Future<PreparedVideo?> prepareVideoImpl({
  required String blobUrl,
  required int originalSize,
  required int maxSeconds,
  required int keepOriginalBytes,
  void Function(double progress)? onProgress,
}) async {
  final video = html.VideoElement()
    ..src = blobUrl
    ..preload = 'auto'
    ..setAttribute('playsinline', 'true');
  Object? ac;
  html.MediaStream? stream;
  double dur = double.nan;
  try {
    try {
      await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));
    } catch (_) {
      return null; // لا نستطيع قراءته هنا: يُرفع الأصلي إن كان مسموحاً
    }
    dur = video.duration.toDouble();
    final w = video.videoWidth, h = video.videoHeight;
    if (w == 0 || h == 0) return null;
    final tooLong = dur.isFinite && dur > maxSeconds + 0.5;
    if (!tooLong && originalSize <= keepOriginalBytes) return null;

    final mime = _pickMime();
    if (mime == null) {
      if (tooLong) throw StateError(_tooLongMsg(maxSeconds));
      return null;
    }

    final limit = dur.isFinite ? math.min(dur, maxSeconds.toDouble()) : maxSeconds.toDouble();
    final scale = math.min(1.0, 1280 / math.max(w, h));
    final cw = math.max(2, (w * scale / 2).round() * 2);
    final ch = math.max(2, (h * scale / 2).round() * 2);
    final canvas = html.CanvasElement(width: cw, height: ch);
    final ctx = canvas.context2D;
    stream = canvas.captureStream(30);

    // الصوت: نمرّره عبر WebAudio إلى المسجّل دون إخراجه للسماعات.
    try {
      // بلا dart:web_audio (أُزيلت من SDK): نستدعي Web Audio عبر js_util.
      Object? ctor = js_util.getProperty<Object?>(html.window, 'AudioContext');
      ctor ??= js_util.getProperty<Object?>(html.window, 'webkitAudioContext');
      if (ctor != null) {
        final Object ctx = js_util.callConstructor<Object>(ctor, <Object?>[]);
        ac = ctx;
        final Object src = js_util
            .callMethod<Object>(ctx, 'createMediaElementSource', <Object?>[video]);
        final Object dest = js_util
            .callMethod<Object>(ctx, 'createMediaStreamDestination', <Object?>[]);
        js_util.callMethod<void>(src, 'connect', <Object?>[dest]);
        final Object? destStream = js_util.getProperty<Object?>(dest, 'stream');
        if (destStream != null) {
          final tracks = js_util
              .callMethod<Object>(destStream, 'getAudioTracks', <Object?>[]);
          final n = js_util.getProperty<int>(tracks, 'length');
          for (var i = 0; i < n; i++) {
            final t = js_util.getProperty<Object>(tracks, i);
            stream.addTrack(t as html.MediaStreamTrack);
          }
        }
      }
    } catch (_) {}

    final rec = html.MediaRecorder(stream, {
      'mimeType': mime,
      'videoBitsPerSecond': 2500000,
      'audioBitsPerSecond': 96000,
    });
    final chunks = <html.Blob>[];
    rec.addEventListener('dataavailable', (e) {
      final d = (e as html.BlobEvent).data;
      if (d != null && d.size > 0) chunks.add(d);
    });
    final stopped = Completer<void>();
    rec.addEventListener('stop', (_) {
      if (!stopped.isCompleted) stopped.complete();
    });

    final finished = Completer<void>();
    video.onEnded.listen((_) {
      if (!finished.isCompleted) finished.complete();
    });
    video.onError.listen((_) {
      if (!finished.isCompleted) finished.completeError(Exception('video'));
    });

    rec.start(1000);
    await video.play();

    void draw(num _) {
      if (finished.isCompleted) return;
      try {
        ctx.drawImageScaled(video, 0, 0, cw, ch);
      } catch (_) {}
      final t = video.currentTime.toDouble();
      onProgress?.call((t / limit).clamp(0.0, 1.0));
      if (video.ended || t >= limit) {
        finished.complete();
        return;
      }
      html.window.requestAnimationFrame(draw);
    }

    html.window.requestAnimationFrame(draw);
    await finished.future
        .timeout(Duration(seconds: limit.ceil() + 30));
    video.pause();
    rec.stop();
    await stopped.future.timeout(const Duration(seconds: 15));

    final base = mime.split(';').first;
    final blob = html.Blob(chunks, base);
    final reader = html.FileReader()..readAsArrayBuffer(blob);
    await reader.onLoadEnd.first;
    final r = reader.result;
    final Uint8List bytes = r is Uint8List
        ? r
        : (r is ByteBuffer ? r.asUint8List() : Uint8List(0));
    if (bytes.isEmpty) {
      if (tooLong) throw StateError(_tooLongMsg(maxSeconds));
      return null;
    }
    onProgress?.call(1);
    return PreparedVideo(bytes, base);
  } on StateError {
    rethrow;
  } catch (_) {
    if (dur.isFinite && dur > maxSeconds + 0.5) {
      throw StateError(_tooLongMsg(maxSeconds));
    }
    return null;
  } finally {
    try {
      video.pause();
      video.removeAttribute('src');
      video.load();
    } catch (_) {}
    try {
      for (final t in stream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
        t.stop();
      }
    } catch (_) {}
    try {
      final c = ac;
      if (c != null) js_util.callMethod<void>(c, 'close', <Object?>[]);
    } catch (_) {}
  }
}

Future<VideoSize?> probeVideoSizeImpl(String blobUrl) async {
  final video = html.VideoElement()
    ..src = blobUrl
    ..preload = 'metadata'
    ..setAttribute('playsinline', 'true');
  try {
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));
    final w = video.videoWidth, h = video.videoHeight;
    if (w == 0 || h == 0) return null;
    return VideoSize(w, h);
  } catch (_) {
    return null;
  } finally {
    try {
      video.removeAttribute('src');
      video.load();
    } catch (_) {}
  }
}

Future<VideoPoster?> grabVideoPosterImpl(String blobUrl) async {
  final video = html.VideoElement()
    ..src = blobUrl
    ..preload = 'auto'
    ..muted = true
    ..setAttribute('playsinline', 'true');
  try {
    await video.onLoadedData.first.timeout(const Duration(seconds: 15));
    final w = video.videoWidth, h = video.videoHeight;
    if (w == 0 || h == 0) return null;
    try {
      final d = video.duration.toDouble();
      video.currentTime = d.isFinite ? math.min(0.3, d / 2) : 0.1;
      await video.onSeeked.first.timeout(const Duration(seconds: 5));
    } catch (_) {}
    final scale = math.min(1.0, 1080 / math.max(w, h));
    final cw = math.max(2, (w * scale).round());
    final ch = math.max(2, (h * scale).round());
    final canvas = html.CanvasElement(width: cw, height: ch);
    canvas.context2D.drawImageScaled(video, 0, 0, cw, ch);
    final url = canvas.toDataUrl('image/jpeg', 0.8);
    final bytes = UriData.parse(url).contentAsBytes();
    if (bytes.isEmpty) return null;
    return VideoPoster(Uint8List.fromList(bytes), VideoSize(w, h));
  } catch (_) {
    return null;
  } finally {
    try {
      video.pause();
      video.removeAttribute('src');
      video.load();
    } catch (_) {}
  }
}

String _tooLongMsg(int s) =>
    trf('تعذّر تقصير الفيديو على هذا المتصفح. اختر فيديو أقصر من {0} ثانية', [s]);
