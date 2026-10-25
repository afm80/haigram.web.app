import 'dart:typed_data';

/// فيديو جاهز للرفع بعد الضغط والقص داخل المتصفح.
class PreparedVideo {
  final Uint8List bytes;

  /// نوع الملف بلا ترميزات، مثل video/mp4 أو video/webm (يقبلهما الـ Worker).
  final String mime;
  const PreparedVideo(this.bytes, this.mime);
}
