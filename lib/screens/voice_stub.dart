// الرسائل الصوتية: غير مدعومة خارج الويب (يُخفى زر الميكروفون).
import 'dart:typed_data';

const int voiceMaxSeconds = 120;

class VoiceClip {
  final Uint8List bytes;
  final String mime;
  final String ext;
  final int seconds;
  final String wave;
  const VoiceClip(this.bytes, this.mime, this.ext, this.seconds,
      [this.wave = '']);
}

class VoiceRecorder {
  static bool get supported => false;
  Future<void> start() async =>
      throw UnsupportedError('voice recording is not supported here');
  Future<VoiceClip?> stop() async => null;
  void cancel() {}
}

class VoicePlayer {
  static bool get supported => false;
  VoicePlayer(String url);
  bool get playing => false;
  double get position => 0;
  double get speed => 1;
  set speed(double v) {}
  Future<void> toggle() async {}
  void addListener(void Function() listener) {}
  void removeListener(void Function() listener) {}
  void dispose() {}
}
