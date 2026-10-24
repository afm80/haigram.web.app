// تسجيل وتشغيل الرسائل الصوتية على الويب (بلا حزم إضافية).
// التسجيل: Opus أحادي 24 كيلوبت/ث مع إلغاء الضوضاء والصدى وضبط المستوى،
// والضغط يتم أثناء التسجيل نفسه. بديل المتصفحات بلا Opus: AAC بـ 32 كيلوبت.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:web_audio' as wa;

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

class _Format {
  final String recorderMime;
  final String mime;
  final String ext;
  final int bitrate;
  const _Format(this.recorderMime, this.mime, this.ext, this.bitrate);
}

const _formats = <_Format>[
  _Format('audio/webm;codecs=opus', 'audio/webm', 'webm', 24000),
  _Format('audio/ogg;codecs=opus', 'audio/ogg', 'ogg', 24000),
  _Format('audio/mp4;codecs=mp4a.40.2', 'audio/mp4', 'm4a', 32000),
  _Format('audio/mp4', 'audio/mp4', 'm4a', 32000),
];

_Format? _pickFormat() {
  try {
    for (final f in _formats) {
      if (html.MediaRecorder.isTypeSupported(f.recorderMime)) return f;
    }
  } catch (_) {}
  return null;
}

class VoiceRecorder {
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];
  final Stopwatch _clock = Stopwatch();
  _Format? _format;
  wa.AudioContext? _ctx;
  Timer? _sampler;
  final List<double> _levels = [];

  static bool get supported =>
      html.window.navigator.mediaDevices != null && _pickFormat() != null;

  /// يطلب صلاحية الميكروفون ويبدأ التسجيل (يُستدعى من ضغطة المستخدم).
  Future<void> start() async {
    final format = _pickFormat();
    final devices = html.window.navigator.mediaDevices;
    if (format == null || devices == null) {
      throw UnsupportedError('voice recording is not supported');
    }
    final stream = await devices.getUserMedia({
      'audio': {
        'channelCount': 1,
        'sampleRate': 16000,
        'noiseSuppression': true,
        'echoCancellation': true,
        'autoGainControl': true,
      },
    });
    _stream = stream;
    _format = format;
    _chunks.clear();
    final recorder = html.MediaRecorder(stream, {
      'mimeType': format.recorderMime,
      'audioBitsPerSecond': format.bitrate,
    });
    recorder.addEventListener('dataavailable', (event) {
      final data = (event as html.BlobEvent).data;
      if (data != null && data.size > 0) _chunks.add(data);
    });
    _recorder = recorder;
    _startMeter(stream);
    recorder.start(1000);
    _clock
      ..reset()
      ..start();
  }

  /// يقيس علوّ الصوت كل 100ms لرسم الموجة؛ فشله لا يوقف التسجيل.
  void _startMeter(html.MediaStream stream) {
    _levels.clear();
    try {
      final ctx = wa.AudioContext();
      final analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      ctx.createMediaStreamSource(stream).connectNode(analyser);
      try {
        ctx.resume();
      } catch (_) {}
      _ctx = ctx;
      final buf = Uint8List(512);
      _sampler = Timer.periodic(const Duration(milliseconds: 100), (_) {
        try {
          analyser.getByteTimeDomainData(buf);
          var peak = 0;
          for (final v in buf) {
            final d = (v - 128).abs();
            if (d > peak) peak = d;
          }
          _levels.add(peak / 128);
        } catch (_) {}
      });
    } catch (_) {}
  }

  String _buildWave() {
    const bars = 40;
    if (_levels.length < 4) return '';
    final out = StringBuffer();
    var top = 0.0;
    for (final v in _levels) {
      if (v > top) top = v;
    }
    if (top <= 0.02) return '';
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

  void _release() {
    _sampler?.cancel();
    _sampler = null;
    try {
      _ctx?.close();
    } catch (_) {}
    _ctx = null;
    _clock.stop();
    for (final track in _stream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
    _recorder = null;
  }

  /// يوقف التسجيل ويعيد المقطع، أو null إن كان فارغاً.
  Future<VoiceClip?> stop() async {
    final recorder = _recorder;
    final format = _format;
    if (recorder == null || format == null) return null;
    final seconds = (_clock.elapsedMilliseconds / 1000).round();
    final done = Completer<void>();
    recorder.addEventListener('stop', (_) {
      if (!done.isCompleted) done.complete();
    });
    if (recorder.state != 'inactive') recorder.stop();
    await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    final wave = _buildWave();
    _release();
    if (_chunks.isEmpty) return null;
    final blob = html.Blob(List<html.Blob>.of(_chunks), format.mime);
    _chunks.clear();
    final reader = html.FileReader()..readAsArrayBuffer(blob);
    await reader.onLoadEnd.first;
    final result = reader.result;
    final bytes = result is Uint8List
        ? result
        : (result as ByteBuffer).asUint8List();
    if (bytes.isEmpty) return null;
    return VoiceClip(
        bytes, format.mime, format.ext, seconds < 1 ? 1 : seconds, wave);
  }

  /// يلغي التسجيل ويتجاهل ما سُجّل.
  void cancel() {
    final recorder = _recorder;
    try {
      if (recorder != null && recorder.state != 'inactive') recorder.stop();
    } catch (_) {}
    _chunks.clear();
    _release();
  }
}

/// مشغّل رسالة صوتية واحدة؛ يوقف أي رسالة أخرى تعمل في الوقت نفسه.
class VoicePlayer {
  static VoicePlayer? _current;
  static bool get supported => true;

  final html.AudioElement _audio;
  final List<void Function()> _listeners = [];
  bool _disposed = false;

  VoicePlayer(String url) : _audio = html.AudioElement() {
    _audio
      ..src = url
      ..preload = 'none';
    _audio.onTimeUpdate.listen((_) => _notify());
    _audio.onPlay.listen((_) => _notify());
    _audio.onPause.listen((_) => _notify());
    _audio.onEnded.listen((_) {
      _audio.currentTime = 0;
      _notify();
    });
  }

  bool get playing => !_audio.paused && !_audio.ended;
  double get position => _audio.currentTime.toDouble();

  /// سرعة التشغيل (1 / 1.5 / 2).
  double get speed => _audio.playbackRate.toDouble();
  set speed(double v) => _audio.playbackRate = v;

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
      _audio.pause();
      return;
    }
    final other = _current;
    if (other != null && other != this) other._audio.pause();
    _current = this;
    await _audio.play();
  }

  void dispose() {
    _disposed = true;
    _audio.pause();
    _audio.removeAttribute('src');
    _listeners.clear();
    if (_current == this) _current = null;
  }
}
