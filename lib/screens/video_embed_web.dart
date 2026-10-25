// مشغّل الفيديو للويب: iframe مباشر (الطريقة الرسمية لكل منصة).
// الرابط المباشر يُرسل مصدر الصفحة تلقائياً فلا يظهر خطأ «إعداد المشغّل».
// ملف الفيديو والبث (HLS) يُعرضان في iframe بصفحة HTML خاصة (srcdoc) معزولة.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../video_source.dart';

final _registered = <String>{};
final _frames = <String, html.IFrameElement>{};

/// [onResult] يُستدعى بـ true/false عند معرفة نجاح تشغيل ملف أو بث
/// (المنصات الأخرى لا تخبرنا بنتيجتها).
/// [tiktok]: نمط الشورتز العمودي (ملف مرفوع): يملأ الإطار بلا أزرار مشغّل،
/// وتتولى صفحة المشغّل اللمس وترسله عبر [onGesture]
/// ('next' ، 'prev' ، 'paused' ، 'playing' ، 'dbl:x,y').
/// [handle]: للتحكم بالتشغيل والإيقاف من خارج المشغّل.
Widget buildVideoEmbed(VideoSource source,
    {Key? key,
    double? aspect,
    void Function(bool ok)? onResult,
    VideoHandle? handle,
    void Function(String gesture)? onGesture,
    bool tiktok = false}) {
  final tt = tiktok && source.usesPlayerHtml;
  final viewType = 'haigram-v-${source.key}${tt ? '-tt' : ''}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'accelerometer; autoplay; clipboard-write; '
            'encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen'
        ..allowFullscreen = true;
      if (source.usesPlayerHtml) {
        iframe.setAttribute('sandbox', 'allow-scripts allow-presentation');
        iframe.srcdoc = source.playerHtml(short: tt, gestures: tt);
      } else {
        iframe.src = source.embedUrl(
            parentHost: html.window.location.hostname ?? 'haigram.web.app');
      }
      _frames[viewType] = iframe;
      return iframe;
    });
  }
  return _WebVideo(
      key: key,
      viewType: viewType,
      aspect: aspect ?? source.aspect,
      fill: tt,
      handle: tt ? handle : null,
      onGesture: tt ? onGesture : null,
      listen: source.usesPlayerHtml ? onResult : null);
}

class _WebVideo extends StatefulWidget {
  final String viewType;
  final double aspect;
  final void Function(bool ok)? listen;
  final bool fill;
  final VideoHandle? handle;
  final void Function(String gesture)? onGesture;
  const _WebVideo(
      {super.key,
      required this.viewType,
      required this.aspect,
      this.listen,
      this.fill = false,
      this.handle,
      this.onGesture});

  @override
  State<_WebVideo> createState() => _WebVideoState();
}

class _WebVideoState extends State<_WebVideo> {
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    widget.handle?.attach((cmd) {
      _frames[widget.viewType]
          ?.contentWindow
          ?.postMessage({'haigramCmd': cmd}, '*');
    });
    if (widget.listen != null || widget.onGesture != null) {
      _sub = html.window.onMessage.listen((e) {
        final d = e.data;
        if (d is! Map) return;
        if (d['haigramVideo'] != null) {
          widget.listen?.call(d['haigramVideo'] == 'ok');
        }
        final g = d['haigramGesture'];
        if (g is String) widget.onGesture?.call(g);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.handle?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.fill
      ? SizedBox.expand(child: HtmlElementView(viewType: widget.viewType))
      : AspectRatio(
          aspectRatio: widget.aspect,
          child: HtmlElementView(viewType: widget.viewType),
        );
}
