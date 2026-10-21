// غلاف الفيديو: صورة المنصة المصغّرة إن وُجدت، وإلا غلاف يُرسم بالكود:
//  • المنصات (فيميو، تويتش، تيك توك...): لون المنصة واسمها فقط.
//  • ملف الفيديو والبث: شعار Haigram ونص «شاهد الفيديو» / «شاهد البث المباشر».
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../video_source.dart';

class VideoCover extends StatelessWidget {
  final VideoSource source;
  final BoxFit fit;

  /// أيقونة التشغيل في الوسط (تُخفى في المربعات الصغيرة التي لها أيقونتها).
  final bool showPlay;
  const VideoCover(
      {super.key,
      required this.source,
      this.fit = BoxFit.cover,
      this.showPlay = false});

  @override
  Widget build(BuildContext context) {
    final thumb = source.thumbUrl;
    final brand = _BrandCover(source: source, showPlay: showPlay);
    if (thumb == null) return brand;
    return Stack(
      fit: StackFit.expand,
      children: [
        // يظهر غلاف المنصة تحت الصورة، فيبقى مكانها مملوءاً أثناء التحميل أو عند الفشل.
        brand,
        IgnorePointer(
          child: CachedNetworkImage(
            imageUrl: thumb,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 120),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _BrandCover extends StatelessWidget {
  final VideoSource source;
  final bool showPlay;
  const _BrandCover({required this.source, required this.showPlay});

  @override
  Widget build(BuildContext context) {
    final colors = source.brandColors;
    final generic = source.usesPlayerHtml;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : 160.0;
        final tiny = w < 130;
        final size = (w * 0.13).clamp(12.0, 28.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // الاسم أعلى الوسط قليلاً ليبقى مكان أيقونة التشغيل تحته فارغاً.
            Align(
              alignment: const Alignment(0, -0.28),
              child: Padding(
                padding: EdgeInsets.all(tiny ? 6 : 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: generic
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/haigram-mark-dark.png',
                              width: size * 1.8,
                              height: size * 1.8,
                              fit: BoxFit.contain,
                            ),
                            SizedBox(width: size * 0.5),
                            Text(
                              source.coverLabel,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: size,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        )
                      : Text(
                          source.platformName,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: size * 1.25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3),
                        ),
                ),
              ),
            ),
            if (source.isLive && !tiny)
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(tr('مباشر'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            if (showPlay)
              Align(
                alignment: const Alignment(0, 0.45),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                      color: Color(0x99000000), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 36),
                ),
              ),
          ],
        );
      }),
    );
  }
}
