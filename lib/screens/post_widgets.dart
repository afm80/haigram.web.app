import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

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

  Future<void> _sharePost() async {
    final post = widget.post;
    final text = [
      if (post.caption.isNotEmpty) post.caption,
      'شاهد هذا المنشور على Haigram',
      PostService.postLink(post),
    ].join('\n');
    try {
      final result = await Share.share(text, subject: 'منشور على Haigram');
      if (result.status == ShareResultStatus.unavailable) {
        await _copyPostLink();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذرت مشاركة المنشور: $error')),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشور؟'),
        content: const Text('لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await PostService.deletePost(widget.post);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mine = p.uid == PostService.uidOrEmpty;
    final isText = p.type == PostType.text;
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPostForeground = colors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(p, mine),
        StreamBuilder<bool>(
          stream: PostService.isLiked(p.id),
          builder: (context, s) {
            _liked = s.data ?? false;
            return GestureDetector(
              onDoubleTap: _doubleTapLike,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isText)
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 160),
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: isDark
                                ? const [Color(0xFF7C2D12), Color(0xFF431407)]
                                : const [Color(0xFFFFE4E6), Color(0xFFFFF1E6)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft),
                      ),
                      child: Text.rich(
                          _captionSpans(
                              p.caption,
                              TextStyle(
                                  color: textPostForeground,
                                  fontSize: 20,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600)),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textPostForeground)),
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
                          size: 100, color: Colors.white),
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
        if (!isText && p.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${p.username} ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => openProfile(context, p.uid),
                  ),
                  ..._captionSpans(p.caption, null).children!,
                ],
              ),
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

  Widget _header(Post p, bool mine) {
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
              if (v == 'delete') _confirmDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'link', child: Text('نسخ رابط المنشور')),
              if (mine)
                const PopupMenuItem(
                    value: 'delete', child: Text('حذف المنشور')),
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
                      ? AppColors.postLike
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
            onPressed: _sharePost,
            icon: Transform.scale(
              scaleX: -1,
              child: Icon(Icons.send_outlined,
                  size: 26, color: context.appColors.text),
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
                  color: context.appColors.text,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// يميز الهاشتاقات داخل النص.
TextSpan _captionSpans(String text, TextStyle? style) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in RegExp(r'#[\p{L}\p{N}_]+', unicode: true).allMatches(text)) {
    if (m.start > last)
      spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(
        text: m.group(0), style: const TextStyle(fontWeight: FontWeight.w600)));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: style, children: spans);
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
        imageUrl: post.mediaUrl!,
        width: double.infinity,
        height: height,
        fit: fit,
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
            gaplessPlayback: true);
      },
    );
  }
}
