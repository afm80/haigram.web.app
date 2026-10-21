// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// الويب: تنزيل الصورة مباشرة إلى الجهاز.
Future<bool> saveImageFromUrl(String url) async {
  final name = 'haigram_${DateTime.now().millisecondsSinceEpoch}.jpg';
  try {
    final request = await html.HttpRequest.request(url, responseType: 'blob');
    final blob = request.response as html.Blob;
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: objectUrl)..download = name;
    html.document.body?.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(objectUrl);
    return true;
  } catch (_) {
    try {
      final a = html.AnchorElement(href: url)
        ..download = name
        ..target = '_blank';
      html.document.body?.append(a);
      a.click();
      a.remove();
      return true;
    } catch (_) {
      return false;
    }
  }
}
