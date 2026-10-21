// مشغّل الفيديو لتطبيق أندرويد/آيفون.
// يستخدم WebView مباشرة ويرسل ترويسة Referer، لأن يوتيوب يرفض التضمين بدونها
// (خطأ 153 «Video player configuration error») داخل WebView الأندرويد،
// وتويتش يطلب النطاق نفسه (parent)، بينما المتصفح على الموقع يرسلها تلقائياً.
// التشغيل داخل التطبيق حصراً: لا يُفتح أي رابط خارجي.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../video_source.dart';

/// نفس عنوان الموقع المنشور؛ المنصات تتعرّف على التطبيق من خلاله.
const _kReferer = 'https://haigram.web.app/';

/// [onResult] يُستدعى بنجاح/فشل تشغيل ملف أو بث فقط (المنصات لا تخبرنا).
Widget buildVideoEmbed(VideoSource source,
        {Key? key, double? aspect, void Function(bool ok)? onResult}) =>
    _NativeVideo(
        key: key,
        source: source,
        aspect: aspect ?? source.aspect,
        onResult: onResult);

class _NativeVideo extends StatefulWidget {
  final VideoSource source;
  final double aspect;
  final void Function(bool ok)? onResult;
  const _NativeVideo(
      {super.key, required this.source, required this.aspect, this.onResult});

  @override
  State<_NativeVideo> createState() => _NativeVideoState();
}

class _NativeVideoState extends State<_NativeVideo> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('HaigramVideo', onMessageReceived: (m) {
        widget.onResult?.call(m.message == 'ok');
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          // الإطارات الفرعية (إعلانات، مشغّلات داخلية) لا نتدخل فيها.
          if (!req.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(req.url);
          if (req.url == 'about:blank' ||
              req.url.startsWith('data:') ||
              (uri != null && source.allowsNavigation(uri))) {
            return NavigationDecision.navigate;
          }
          // التشغيل داخل التطبيق فقط: أي رابط آخر (شعار المنصة مثلاً) يُمنع
          // ولا يُفتح في متصفح أو تطبيق المنصة.
          return NavigationDecision.prevent;
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // يسمح بالتشغيل التلقائي بعد نقر المستخدم على الصورة المصغّرة.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    if (source.usesPlayerHtml) {
      _controller.loadHtmlString(source.playerHtml(), baseUrl: _kReferer);
    } else {
      var url = source.embedUrl()!;
      if (source.provider == VideoProvider.youtube) url += '&fs=0';
      _controller.loadRequest(Uri.parse(url), headers: const {'Referer': _kReferer});
    }
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: widget.aspect,
        child: WebViewWidget(controller: _controller),
      );
}
