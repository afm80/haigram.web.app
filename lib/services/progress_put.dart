import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// طلب PUT يرسل الجسم على دفعات صغيرة ويبلّغ عن التقدّم.
/// على أندرويد التقدّم حقيقي (الإرسال يتوقف عند امتلاء مخزن الشبكة)،
/// وعلى الويب يحمّل المتصفح الجسم كاملاً قبل الإرسال فيقفز التقدّم سريعاً.
class ProgressPutRequest extends http.BaseRequest {
  ProgressPutRequest(Uri url, this.bytes, {this.onProgress})
      : super('PUT', url) {
    contentLength = bytes.length;
  }

  final Uint8List bytes;
  final void Function(double progress)? onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    const chunk = 128 * 1024;
    var sent = 0;
    var reported = 0.0;
    while (sent < bytes.length) {
      final end = math.min(bytes.length, sent + chunk);
      yield Uint8List.sublistView(bytes, sent, end);
      sent = end;
      // نترك آخر 3% حتى يصل ردّ الخادم، ونخفّف عدد التحديثات (كل 1%).
      final p = sent / bytes.length * 0.97;
      if (p - reported >= 0.01) {
        reported = p;
        onProgress?.call(p);
      }
    }
  }
}
