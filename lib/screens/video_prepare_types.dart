import 'dart:typed_data';

/// فيديو جاهز للرفع بعد الضغط والقص داخل المتصفح.
class PreparedVideo {
  final Uint8List bytes;

  /// نوع الملف بلا ترميزات، مثل video/mp4 أو video/webm (يقبلهما الـ Worker).
  final String mime;
  const PreparedVideo(this.bytes, this.mime);
}

/// أبعاد الفيديو كما تظهر للمشاهد (بعد مراعاة التدوير).
class VideoSize {
  final int width;
  final int height;
  const VideoSize(this.width, this.height);

  /// عمودي بوضوح (مثل 9:16 أو 3:4): يُعرض مع الشورتز.
  bool get isVertical => width > 0 && height >= width * 1.2;
}

/// لقطة غلاف من الفيديو (JPEG) مع أبعاده.
class VideoPoster {
  final Uint8List jpeg;
  final VideoSize size;
  const VideoPoster(this.jpeg, this.size);
}
