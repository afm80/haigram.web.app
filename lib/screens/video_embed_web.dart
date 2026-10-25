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

/// [onResult] يُستدعى بـ true/false عند معرفة نجاح تشغيل ملف أو بث
/// (المنصات الأخرى لا تخبرنا بنتيجتها).
/// [handle] و[tiktok] للتوافق مع نسخة الأندرويد؛ عرض الويب لا يستعملهما.
Widget buildVideoEmbed(VideoSource source,
    {Key? key,
    double? aspect,
    void Function(bool ok)? onResult,
    VideoHandle? handle,
    bool tiktok = false}) {
  final viewType = 'haigram-v-${source.key}';
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
        iframe.srcdoc = source.playerHtml();
      } else {
        iframe.src = source.embedUrl(
            parentHost: html.window.location.hostname ?? 'haigram.web.app');
      }
      return iframe;
    });
  }
  return _WebVideo(
      key: key,
      viewType: viewType,
      aspect: aspect ?? source.aspect,
      listen: source.usesPlayerHtml ? onResult : null);
}

class _WebVideo extends StatefulWidget {
  final String viewType;
  final double aspect;
  final void Function(bool ok)? listen;
  const _WebVideo(
      {super.key, required this.viewType, required this.aspect, this.listen});

  @override
  State<_WebVideo> createState() => _WebVideoState();
}

class _WebVideoState extends State<_WebVideo> {
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.listen != null) {
      _sub = html.window.onMessage.listen((e) {
        final d = e.data;
        if (d is Map && d['haigramVideo'] != null) {
          widget.listen!(d['haigramVideo'] == 'ok');
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: widget.aspect,
        child: HtmlElementView(viewType: widget.viewType),
      );
}
