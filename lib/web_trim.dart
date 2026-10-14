// الويب يستخدم ffmpeg.wasm عبر dart:js_interop، وغيره (أندرويد) يستخدم نسخة بسيطة.
export 'web_trim_stub.dart' if (dart.library.js_interop) 'web_trim_web.dart';
