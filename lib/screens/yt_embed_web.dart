// مشغّل يوتيوب للويب: iframe مباشر (الطريقة الرسمية من يوتيوب).
// الرابط المباشر يُرسل مصدر الصفحة تلقائياً فلا يظهر خطأ «إعداد المشغّل».
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final _registered = <String>{};

Widget buildYoutubeEmbed(String videoId, {double aspect = 16 / 9}) {
  final viewType = 'haigram-yt-$videoId';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = 'https://www.youtube.com/embed/$videoId'
            '?autoplay=1&playsinline=1&rel=0'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'accelerometer; autoplay; clipboard-write; '
            'encrypted-media; gyroscope; picture-in-picture; web-share'
        ..allowFullscreen = true;
      return iframe;
    });
  }
  return AspectRatio(
    aspectRatio: aspect,
    child: HtmlElementView(viewType: viewType),
  );
}
