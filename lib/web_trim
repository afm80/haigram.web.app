import 'dart:js_interop';
import 'dart:typed_data';

@JS('lamhaTrim')
external JSPromise<JSUint8Array> _lamhaTrim(JSString url, JSString ext, JSNumber seconds);

@JS('lamhaBlobUrl')
external JSString _lamhaBlobUrl(JSUint8Array data, JSString mime);

/// ينشئ رابط blob محلياً من بايتات لتشغيلها أو عرضها.
String makeBlobUrl(Uint8List bytes, String mime) => _lamhaBlobUrl(bytes.toJS, mime.toJS).toDart;

/// يقص الفيديو إلى [seconds] ثانية (بدون إعادة ترميز) ويعيد ملف MP4.
Future<Uint8List> trimVideo(String blobUrl, String ext, int seconds) async {
  final result = await _lamhaTrim(blobUrl.toJS, ext.toJS, seconds.toJS).toDart;
  return result.toDart;
}
