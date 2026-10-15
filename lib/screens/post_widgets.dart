import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/post_service.dart';
import '../theme.dart';
import '../route_state.dart';
import 'common_widgets.dart';
import 'explore_screen.dart' show ExploreSearchScreen;
import 'share_sheet.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  return 'قبل ${d.inDays} يوم';
}

/// منشور بتصميم إنستغرام: رأس + وسائط + أزرار + إعجابات + وصف + تعليقات.
class PostCard extends StatefulWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _liked = false;
  bool _heart = false;

  void _doubleTapLike() {
    if (!_liked) PostService.toggleLike(widget.post.id, false);
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  Future<void> _copyPostLink() async {
    await Clipboard.setData(
        ClipboardData(text: PostService.postLink(widget.post)));
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم نسخ رابط المنشور')));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final isText = p.type == PostType.text;
    final colors = context.appColors;
    final textPostForeground = colors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(p),
        StreamBuilder<bool>(
          stream: PostService.isLiked(p.id),
          builder: (context, s) {
            _liked = s.data ?? false;
            return GestureDetector(
              onDoubleTap: _doubleTapLike,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (p.hasVideo)
                    _videoBlock(p)
                  else if (isText)
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 160),
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      // الخلفية تتبع الوضع: داكنة في الداكن وفاتحة في الفاتح.
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.symmetric(
                          horizontal: BorderSide(
                              color: colors.text.withOpacity(0.08)),
                        ),
                      ),
                      child: LinkText(
                        text: p.caption,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: textPostForeground,
                            fontSize: 20,
                            height: 1.5,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, c) {
                        final mediaHeight =
                            (MediaQuery.sizeOf(context).height * 0.62)
                                .clamp(1.0, c.maxWidth * 1.25)
                                .toDouble();
                        return SizedBox(
                          width: double.infinity,
                          height: mediaHeight,
                          child: PostImage(
                            post: p,
                            fit: BoxFit.contain,
                            height: mediaHeight,
                          ),
                        );
                      },
                    ),
                  AnimatedScale(
                    scale: _heart ? 1 : 0.3,
                    duration: const Duration(milliseconds: 250),
                    child: AnimatedOpacity(
                      opacity: _heart ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.favorite_rounded,
                          size: 100,
                          color: AppColors.brandOrange,
                          shadows: [
                            Shadow(blurRadius: 24, color: Color(0x66000000))
                          ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        _actions(p),
        LikeBuilder(
          post: p,
          builder: (context, liked, count, toggle) => count > 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Text('$count إعجاب',
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w700)),
                )
              : const SizedBox.shrink(),
        ),
        if ((!isText || p.hasVideo) && p.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: LinkText(
              text: p.caption,
              leading: '${p.username} ',
              onLeadingTap: () => openProfile(context, p.uid),
              style: TextStyle(color: colors.text, height: 1.4),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: GestureDetector(
            onTap: () => showCommentsSheet(context, p),
            child: Text(
              p.comments > 0
                  ? 'عرض كل ${p.comments} تعليقات'
                  : 'أضف تعليقاً...',
              style: TextStyle(color: context.appColors.textDim, fontSize: 14),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
          child: Text(timeAgo(p.createdAt),
              style: TextStyle(color: context.appColors.textDim, fontSize: 11)),
        ),
      ],
    );
  }

  /// بطاقة فيديو يوتيوب: صورة مصغّرة + زر تشغيل، والضغط يفتح الفيديو في يوتيوب.
  Widget _videoBlock(Post p) {
    final id = p.videoId!;
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(PostService.youtubeWatchUrl(id)),
          mode: LaunchMode.externalApplication),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            CachedNetworkImage(
              imageUrl: p.videoThumb!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: Color(0xCCFF0000), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
            PositionedDirectional(
              start: 10,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('YouTube',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Post p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => openProfile(context, p.uid),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                UserAvatar(uid: p.uid, fallbackName: p.username, radius: 17),
                const SizedBox(width: 10),
                Text(p.username,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            color: context.appColors.surfaceHigh,
            onSelected: (v) {
              if (v == 'link') _copyPostLink();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'link', child: Text('نسخ رابط المنشور')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(Post p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          LikeBuilder(
            post: p,
            builder: (context, liked, count, toggle) => IconButton(
              tooltip: 'إعجاب',
              onPressed: toggle,
              icon: AnimatedScale(
                scale: liked ? 1.12 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 28,
                  color: liked
                      ? context.appColors.reaction
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'التعليقات',
            onPressed: () => showCommentsSheet(context, p),
            icon: Icon(
              Icons.mode_comment_outlined,
              size: 26,
              color: context.appColors.text,
            ),
          ),
          IconButton(
            tooltip: 'مشاركة',
            onPressed: () => showPostShareSheet(context, widget.post),
            icon: Transform.scale(
              scaleX: -1,
              child: Icon(Icons.reply_rounded,
                  size: 30, color: context.appColors.text),
            ),
          ),
          const Spacer(),
          StreamBuilder<bool>(
            stream: PostService.isSaved(p.id),
            builder: (context, s) {
              final saved = s.data ?? false;
              return IconButton(
                tooltip: saved ? 'إزالة من المحفوظات' : 'حفظ المنشور',
                onPressed: () => PostService.toggleSave(p.id, saved),
                icon: Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 28,
                  color: saved
                      ? context.appColors.reaction
                      : context.appColors.text,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// نص منشور تُلوَّن فيه الهاشتاقات والروابط وتُفتح عند النقر:
/// الهاشتاق يفتح البحث عنه، والرابط (http/https أو www) يفتح في المتصفح.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? leading; // مثل اسم صاحب المنشور قبل الوصف
  final VoidCallback? onLeadingTap;
  const LinkText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.leading,
    this.onLeadingTap,
  });

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  static final _pattern = RegExp(
      r'(https?://[^\s]+|www\.[^\s]+)|(#[\p{L}\p{N}_]+)',
      unicode: true);
  static const _trailing = '.,!?;:)]}\'"،؛؟';

  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _openTag(String tag) {
    rootNavigatorOf(context).push<void>(appRoute<void>(
        'search', const {}, (_) => ExploreSearchScreen(initialQuery: tag)));
  }

  Future<void> _openUrl(String url) async {
    final fixed = url.startsWith('www.') ? 'https://$url' : url;
    final uri = Uri.tryParse(fixed);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final linkColor = context.appColors.reaction;
    final text = widget.text;
    final spans = <InlineSpan>[];
    if (widget.leading != null) {
      spans.add(TextSpan(
        text: widget.leading,
        style: const TextStyle(fontWeight: FontWeight.w700),
        recognizer:
            widget.onLeadingTap == null ? null : _tap(widget.onLeadingTap!),
      ));
    }
    var last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      var match = m.group(0)!;
      if (m.group(1) != null) {
        // نُبقي علامات الترقيم في نهاية الرابط خارجه.
        var end = match.length;
        while (end > 0 && _trailing.contains(match[end - 1])) {
          end--;
        }
        final url = match.substring(0, end);
        spans.add(TextSpan(
          text: url,
          style: TextStyle(
              color: linkColor, decoration: TextDecoration.underline),
          recognizer: _tap(() => _openUrl(url)),
        ));
        if (end < match.length) spans.add(TextSpan(text: match.substring(end)));
      } else {
        spans.add(TextSpan(
          text: match,
          style: TextStyle(color: linkColor, fontWeight: FontWeight.w600),
          recognizer: _tap(() => _openTag(match)),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}

/// شاشة منشور واحد (عند الضغط على صورة/نص في الملف الشخصي).
class PostDetailScreen extends StatelessWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنشور')),
      body: SafeArea(
        child: StreamBuilder<Post?>(
          stream: PostService.postStream(post.id),
          initialData: post,
          builder: (context, snap) {
            final live = snap.data;
            if (live == null)
              return const Center(child: Text('هذا المنشور لم يعد متاحاً'));
            return ListView(children: [PostCard(post: live)]);
          },
        ),
      ),
    );
  }
}

/// صورة منشور: من رابط Storage أو من Firestore (وضع التجربة).
class PostImage extends StatelessWidget {
  final Post post;
  final BoxFit fit;
  final double? height;
  const PostImage(
      {super.key, required this.post, this.fit = BoxFit.cover, this.height});

  @override
  Widget build(BuildContext context) {
    // نفكّ الصورة بحجم مكان عرضها فقط (وليس بحجمها الأصلي الكبير) لتخفيف الذاكرة.
    return LayoutBuilder(builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final maxW = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final decodeWidth = (maxW * dpr).round().clamp(160, 1080).toInt();
      return _content(context, decodeWidth);
    });
  }

  Widget _content(BuildContext context, int decodeWidth) {
    final loading = SizedBox(
        height: height ?? 240,
        child: const Center(child: CircularProgressIndicator()));
    final broken = SizedBox(
      height: height ?? 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                color: context.appColors.textDim, size: 30),
            SizedBox(height: 6),
            Text('تعذر تحميل الصورة',
                style:
                    TextStyle(color: context.appColors.textDim, fontSize: 12)),
          ],
        ),
      ),
    );
    if (post.mediaUrl != null) {
      return CachedNetworkImage(
        imageUrl: PostService.optimizedImageUrl(post.mediaUrl!, decodeWidth),
        width: double.infinity,
        height: height,
        fit: fit,
        memCacheWidth: decodeWidth,
        placeholder: (_, __) => loading,
        errorWidget: (_, __, ___) => broken,
      );
    }
    if (post.mediaId == null) return broken;
    return FutureBuilder<Uint8List>(
      future: PostService.mediaBytes(post),
      builder: (_, s) {
        if (s.hasError) return broken;
        if (!s.hasData) return loading;
        return Image.memory(s.data!,
            width: double.infinity,
            height: height,
            fit: fit,
            cacheWidth: decodeWidth,
            gaplessPlayback: true);
      },
    );
  }
}
