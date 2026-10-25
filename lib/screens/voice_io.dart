// تسجيل وتشغيل الرسائل الصوتية على أندرويد/iOS (التطبيق الأصلي).
// التسجيل: AAC-LC أحادي 24 كيلوبت/ث داخل m4a (مدعوم على كل الأجهزة والمتصفحات)،
// فيعمل التشغيل على الويب أيضاً. التشغيل عبر حزمة audioplayers.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const int voiceMaxSeconds = 120;

class VoiceClip {
  final Uint8List bytes;
  final String mime;
  final String ext;
  final int seconds;

  /// شكل الموجة: أرقام 0-9 (ارتفاع كل عمود)، أو نص فارغ إن تعذّر القياس.
  final String wave;
  const VoiceClip(this.bytes, this.mime, this.ext, this.seconds,
      [this.wave = '']);
}

class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  final List<double> _levels = [];
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  /// يطلب صلاحية الميكروفون ويبدأ التسجيل (يُستدعى من ضغطة المستخدم).
  Future<void> start() async {
    if (!await _rec.hasPermission()) {
      throw StateError('microphone permission denied');
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 24000,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _path = path;
    _levels.clear();
    _ampSub = _rec
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      // current بالديسيبل (من -160 إلى 0)؛ نحوّل -60..0 إلى 0..1.
      final db = a.current.isFinite ? a.current : -60.0;
      _levels.add(((db + 60) / 60).clamp(0.0, 1.0));
    });
    _clock
      ..reset()
      ..start();
  }

  String _buildWave() {
    const bars = 40;
    if (_levels.length < 4) return '';
    var top = 0.0;
    for (final v in _levels) {
      if (v > top) top = v;
    }
    if (top <= 0.02) return '';
    final out = StringBuffer();
    for (var i = 0; i < bars; i++) {
      final from = (i * _levels.length / bars).floor();
      var to = ((i + 1) * _levels.length / bars).ceil();
      if (to <= from) to = from + 1;
      var peak = 0.0;
      for (var j = from; j < to && j < _levels.length; j++) {
        if (_levels[j] > peak) peak = _levels[j];
      }
      final norm = math.sqrt(peak / top);
      out.write((norm * 9).round().clamp(0, 9));
    }
    return out.toString();
  }

  Future<void> _release() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _clock.stop();
    try {
      await _rec.dispose();
    } catch (_) {}
  }

  /// يوقف التسجيل ويعيد المقطع، أو null إن كان فارغاً.
  Future<VoiceClip?> stop() async {
    final seconds = (_clock.elapsedMilliseconds / 1000).round();
    final wave = _buildWave();
    String? path;
    try {
      path = await _rec.stop() ?? _path;
    } catch (_) {
      path = _path;
    }
    await _release();
    if (path == null) return null;
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return VoiceClip(
          bytes, 'audio/mp4', 'm4a', seconds < 1 ? 1 : seconds, wave);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// يلغي التسجيل ويتجاهل ما سُجّل.
  void cancel() {
    final path = _path;
    () async {
      try {
        await _rec.cancel();
      } catch (_) {}
      await _release();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }();
  }
}

/// مشغّل رسالة صوتية واحدة؛ يوقف أي رسالة أخرى تعمل في الوقت نفسه.
class VoicePlayer {
  static VoicePlayer? _current;
  static bool get supported => true;

  final String _url;
  final AudioPlayer _audio = AudioPlayer();
  final List<void Function()> _listeners = [];
  final List<StreamSubscription<dynamic>> _subs = [];
  PlayerState _state = PlayerState.stopped;
  double _position = 0;
  double _speed = 1;
  bool _disposed = false;

  VoicePlayer(String url) : _url = url {
    _subs.add(_audio.onPlayerStateChanged.listen((s) {
      _state = s;
      _notify();
    }));
    _subs.add(_audio.onPositionChanged.listen((d) {
      _position = d.inMilliseconds / 1000;
      _notify();
    }));
    _subs.add(_audio.onPlayerComplete.listen((_) {
      _position = 0;
      _state = PlayerState.stopped;
      _notify();
    }));
  }

  bool get playing => _state == PlayerState.playing;
  double get position => _position;

  /// سرعة التشغيل (1 / 1.5 / 2).
  double get speed => _speed;
  set speed(double v) {
    _speed = v;
    _audio.setPlaybackRate(v).catchError((_) {});
  }

  void _notify() {
    if (_disposed) return;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<void> toggle() async {
    if (playing) {
      await _audio.pause();
      return;
    }
    final other = _current;
    if (other != null && other != this) {
      try {
        await other._audio.pause();
      } catch (_) {}
    }
    _current = this;
    if (_state == PlayerState.paused) {
      await _audio.resume();
    } else {
      await _audio.play(UrlSource(_url));
    }
    await _audio.setPlaybackRate(_speed);
  }

  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _listeners.clear();
    _audio.dispose();
    if (_current == this) _current = null;
  }
}
