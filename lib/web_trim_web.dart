import 'dart:js_interop';
import 'dart:typed_data';

@JS('lamhaTrim')
external JSPromise<JSUint8Array> _lamhaTrim(JSString url, JSString ext, JSNumber seconds);

@JS('lamhaCompress')
external JSPromise<JSUint8Array> _lamhaCompress(JSString url, JSString ext,
    JSNumber seconds, JSNumber maxShort, JSFunction onProgress);

@JS('lamhaThumb')
external JSPromise<JSUint8Array?> _lamhaThumb(JSString url, JSNumber width);

@JS('lamhaBlobUrl')
external JSString _lamhaBlobUrl(JSUint8Array data, JSString mime);

/// ينشئ رابط blob محلياً من بايتات لتشغيلها أو عرضها.
String makeBlobUrl(Uint8List bytes, String mime) => _lamhaBlobUrl(bytes.toJS, mime.toJS).toDart;

/// يقص الفيديو إلى [seconds] ثانية (بدون إعادة ترميز) ويعيد ملف MP4.
Future<Uint8List> trimVideo(String blobUrl, String ext, int seconds) async {
  final result = await _lamhaTrim(blobUrl.toJS, ext.toJS, seconds.toJS).toDart;
  return result.toDart;
}

/// يضغط الفيديو (H.264 + AAC) ويقصّه إلى [seconds] ثانية ويصغّر ضلعه الأقصر
/// إلى [maxShortSide] بكسل. [onProgress] تستقبل نسبة بين 0 و1.
Future<Uint8List> compressVideo(
  String blobUrl,
  String ext, {
  required int seconds,
  int maxShortSide = 720,
  void Function(double)? onProgress,
}) async {
  final callback = ((JSNumber p) => onProgress?.call(p.toDartDouble)).toJS;
  final result = await _lamhaCompress(blobUrl.toJS, ext.toJS, seconds.toJS,
          maxShortSide.toJS, callback)
      .toDart;
  return result.toDart;
}

/// صورة JPEG مصغّرة من الفيديو، أو null إن تعذّر توليدها.
Future<Uint8List?> videoThumbnail(String blobUrl, {int width = 320}) async {
  try {
    final result = await _lamhaThumb(blobUrl.toJS, width.toJS).toDart;
    return result?.toDart;
  } catch (_) {
    return null;
  }
}
