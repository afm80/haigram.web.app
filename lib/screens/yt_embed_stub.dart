// مشغّل يوتيوب لتطبيق أندرويد/آيفون.
// يستخدم WebView مباشرة ويرسل ترويسة Referer، لأن يوتيوب يرفض التضمين بدونها
// (خطأ 153 «Video player configuration error») داخل WebView الأندرويد،
// بينما المتصفح على الموقع يرسلها تلقائياً فيعمل هناك.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// نفس عنوان الموقع المنشور؛ يوتيوب يتعرّف على التطبيق من خلاله.
const _kReferer = 'https://haigram.web.app/';

Widget buildYoutubeEmbed(String videoId,
        {Key? key, double aspect = 16 / 9}) =>
    _NativeYoutube(key: key, videoId: videoId, aspect: aspect);

class _NativeYoutube extends StatefulWidget {
  final String videoId;
  final double aspect;
  const _NativeYoutube({super.key, required this.videoId, this.aspect = 16 / 9});

  @override
  State<_NativeYoutube> createState() => _NativeYoutubeState();
}

class _NativeYoutubeState extends State<_NativeYoutube> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          final isEmbed = uri != null &&
              uri.host.endsWith('youtube.com') &&
              uri.path.startsWith('/embed/');
          if (isEmbed || req.url == 'about:blank') {
            return NavigationDecision.navigate;
          }
          // أي رابط آخر (شعار يوتيوب مثلاً) يُفتح خارج التطبيق.
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // يسمح بالتشغيل التلقائي بعد نقر المستخدم على الصورة المصغّرة.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.loadRequest(
      Uri.parse('https://www.youtube.com/embed/${widget.videoId}'
          '?autoplay=1&playsinline=1&rel=0&fs=0'),
      headers: const {'Referer': _kReferer},
    );
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: widget.aspect,
        child: WebViewWidget(controller: _controller),
      );
}
