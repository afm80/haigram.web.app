import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/post_service.dart';
import '../auth_gate.dart';
import '../services/social_service.dart';
import '../theme.dart';
import '../route_state.dart';
import 'common_widgets.dart';
import 'explore_screen.dart' show ExploreSearchScreen;
import 'create_flow.dart' show PickedMedia, MediaError, pickAlbumMedia;
import 'post_style.dart';
import 'share_sheet.dart';
import 'short_tiktok.dart';
import 'translate_widgets.dart';
import '../video_source.dart';
import 'video_cover.dart';
import 'video_embed_stub.dart' if (dart.library.html) 'video_embed_web.dart';

import '../l10n.dart';
import '../net_error.dart';
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('الآن');
  if (d.inMinutes < 60) return trf('قبل {0} د', [d.inMinutes]);
  if (d.inHours < 24) return trf('قبل {0} س', [d.inHours]);
  return trf('قبل {0} يوم', [d.inDays]);
}

/// منشور بتصميم إنستغرام: رأس + وسائط + أزرار + إعجابات + وصف + تعليقات.
class PostCard extends StatefulWidget {
  final Post post;
  /// يبدأ فيديو يوتيوب تلقائياً (عند فتح المنشور من الملف الشخصي مثلاً).
  final bool autoPlayVideo;
  /// يعرض النص كاملاً بلا اقتطاع (شاشة المنشور المفرد).
  final bool expandText;
  const PostCard(
      {super.key,
      required this.post,
      this.autoPlayVideo = false,
      this.expandText = false});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _liked = false;
  bool _heart = false;
  Timer? _viewTimer;

  @override
  void initState() {
    super.initState();
    // تُحتسب المشاهدة إذا بقي المنشور ظاهراً أكثر من لحظة.
    _viewTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) PostService.recordPostView(widget.post);
    });
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    super.dispose();
  }

  void _doubleTapLike() {
    if (needsLogin(context)) return;
    if (!_liked) PostService.toggleLike(widget.post.id, false);
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  Future<void> _hideNotInterested(Post p) async {
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.hidePost(p.id);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر الإخفاء')))));
    }
  }

  Future<void> _copyPostLink() async {
    await Clipboard.setData(
        ClipboardData(text: PostService.postLink(widget.post)));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('تم نسخ رابط المنشور'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PostService.hiddenIds,
      builder: (context, ids, _) => ids.contains(widget.post.id)
          ? _HiddenStrip(onUndo: () => PostService.unhidePost(widget.post.id))
          : _cardBody(context),
    );
  }

  Widget _cardBody(BuildContext context) {
    final p = widget.post;
    final isText = p.type == PostType.text;
    final colors = context.appColors;
    final textPostForeground = colors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.repostedFromUsername != null) _repostLabel(p),
        _header(p),
        StreamBuilder<bool>(
          stream: PostService.isLiked(p.id),
          builder: (context, s) {
            _liked = s.data ?? false;
            // الفيديو بلا غلاف نقر مزدوج حتى لا يتعارض مع النقر على المشغّل.
            if (p.hasVideo) return _videoBlock(p);
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
                      constraints: BoxConstraints(
                          minHeight: postBgGradient(p.tbg) != null ? 280 : 160),
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      // الخلفية الملونة إن اختارها صاحب المنشور، وإلا تتبع الوضع:
                      // داكنة في الداكن وفاتحة في الفاتح.
                      decoration: postBgGradient(p.tbg) != null
                          ? BoxDecoration(gradient: postBgGradient(p.tbg))
                          : BoxDecoration(
                              color: colors.surface,
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                    color: colors.text.withOpacity(0.08)),
                              ),
                            ),
                      child: TranslatableText(
                        text: p.caption,
                        centered: true,
                        builder: (shown) => LinkText(
                          text: shown,
                          collapsedLines: widget.expandText ? null : 6,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: postBgGradient(p.tbg) != null
                                  ? (postTextColor(p.tc) ?? Colors.white)
                                  : (postTextColor(p.tc) ?? textPostForeground),
                              fontSize: postBgGradient(p.tbg) != null ? 24 : 20,
                              height: 1.5,
                              fontWeight: postBgGradient(p.tbg) != null
                                  ? FontWeight.w800
                                  : FontWeight.w600),
                        ),
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
                          child: p.isAlbum
                              ? PostAlbumPager(post: p, height: mediaHeight)
                              : PostImage(
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
                          color: AppColors.likeRed,
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
                  child: Text(trf('{0} إعجاب', [count]),
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w700)),
                )
              : const SizedBox.shrink(),
        ),
        if ((!isText || p.hasVideo) && p.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: TranslatableText(
              text: p.caption,
              builder: (shown) => LinkText(
                text: shown,
                collapsedLines: widget.expandText ? null : 2,
                leading: '${p.username} ',
                onLeadingTap: () => openProfile(context, p.uid),
                style: TextStyle(color: colors.text, height: 1.4),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: GestureDetector(
            onTap: () => showCommentsSheet(context, p),
            child: Text(
              p.comments > 0
                  ? trf('عرض كل {0} تعليقات', [p.comments])
                  : tr('أضف تعليقاً...'),
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

  /// فيديو يعمل داخل المنشور نفسه (غلاف/صورة مصغّرة ثم تشغيل عند النقر).
  Widget _videoBlock(Post p) {
    final v = p.video;
    if (v == null) return const SizedBox.shrink();
    return VideoInline(
        key: ValueKey('yt-${p.id}'),
        source: v,
        autoPlay: widget.autoPlayVideo);
  }

  /// «أعاد @فلان نشره» فوق المنشور المُعاد نشره.
  Widget _repostLabel(Post p) {
    final dim = context.appColors.textDim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: p.repostedFromUid == null
          ? null
          : () => openProfile(context, p.repostedFromUid!),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(
          children: [
            Icon(Icons.repeat_rounded, size: 16, color: dim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  trf('أعاد @{0} نشر منشور @{1}', [p.username, p.repostedFromUsername]),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: dim, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleRepost() async {
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final posted = await PostService.toggleRepost(widget.post);
      messenger.showSnackBar(SnackBar(
          content: Text(posted ? tr('تمت إعادة النشر') : tr('تم إلغاء إعادة النشر'))));
    } catch (error) {
      final text =
          error is StateError
              ? error.message
              : friendlyError(error, fallback: tr('تعذرت العملية'));
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
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
            // مشغّل يوتيوب (iframe) يبقى فوق واجهة فلاتر ويلتقط النقرات،
            // فنزيله قبل ظهور القائمة كي تصل النقرة إلى (تعديل/حذف...).
            onOpened: stopInlineVideos,
            onSelected: (v) {
              switch (v) {
                case 'link':
                  _copyPostLink();
                case 'edit':
                  editPostCaption(context, p);
                case 'delete':
                  deletePostWithConfirm(context, p);
                case 'hide':
                  _hideNotInterested(p);
                case 'report':
                  if (needsLogin(context)) return;
                  reportPostSheet(context, p);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'link',
                child: Row(children: [
                  Icon(Icons.link_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(tr('نسخ رابط المنشور')),
                ]),
              ),
              if (p.uid != PostService.uidOrEmpty)
                PopupMenuItem(
                  value: 'hide',
                  child: Row(children: [
                    Icon(Icons.visibility_off_outlined, size: 20),
                    SizedBox(width: 10),
                    Text(tr('غير مهتم')),
                  ]),
                ),
              if (p.uid != PostService.uidOrEmpty)
                PopupMenuItem(
                  value: 'report',
                  child: Row(children: [
                    Icon(Icons.flag_outlined,
                        size: 20, color: AppColors.brandPurple),
                    const SizedBox(width: 10),
                    Text(tr('إبلاغ')),
                  ]),
                ),
              if (p.uid == PostService.uidOrEmpty)
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 20),
                    SizedBox(width: 10),
                    Text(tr('تعديل المنشور')),
                  ]),
                ),
              if (p.uid == PostService.uidOrEmpty)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 20, color: AppColors.brandPurple),
                    const SizedBox(width: 10),
                    Text(tr('حذف المنشور')),
                  ]),
                ),
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
              tooltip: tr('إعجاب'),
              onPressed: toggle,
              icon: AnimatedScale(
                scale: liked ? 1.12 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 28,
                  color: liked
                      ? AppColors.likeRed
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('التعليقات'),
            onPressed: () => showCommentsSheet(context, p),
            icon: Icon(
              Icons.mode_comment_outlined,
              size: 26,
              color: context.appColors.text,
            ),
          ),
          StreamBuilder<bool>(
            stream: PostService.isReposted(p),
            builder: (context, s) {
              final reposted = s.data ?? false;
              return IconButton(
                tooltip: reposted ? tr('إلغاء إعادة النشر') : tr('إعادة النشر'),
                onPressed: _toggleRepost,
                icon: Icon(
                  Icons.repeat_rounded,
                  size: 29,
                  color: reposted
                      ? const Color(0xFF00BA7C)
                      : context.appColors.text,
                ),
              );
            },
          ),
          IconButton(
            tooltip: tr('مشاركة'),
            onPressed: () {
              if (needsLogin(context)) return;
              showPostShareSheet(context, widget.post);
            },
            icon: const _SharePlaneIcon(),
          ),
          const Spacer(),
          StreamBuilder<bool>(
            stream: PostService.isSaved(p.id),
            builder: (context, s) {
              final saved = s.data ?? false;
              return IconButton(
                tooltip: saved ? tr('إزالة من المحفوظات') : tr('حفظ المنشور'),
                onPressed: () {
                  if (needsLogin(context)) return;
                  PostService.toggleSave(p.id, saved);
                },
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

/// شريط يحلّ محل المنشور بعد «غير مهتم» أو الإبلاغ، مع تراجع.
class _HiddenStrip extends StatelessWidget {
  final VoidCallback onUndo;
  const _HiddenStrip({required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.surface,
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 20, color: colors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('تم إخفاء المنشور'),
                style: TextStyle(color: colors.textDim)),
          ),
          TextButton(onPressed: onUndo, child: Text(tr('تراجع'))),
        ],
      ),
    );
  }
}

/// نافذة أسباب الإبلاغ عن منشور؛ بعد الإرسال يُخفى المنشور عن المُبلِّغ.
Future<void> reportPostSheet(BuildContext context, Post post) async {
  await _releaseVideosForDialog();
  if (!context.mounted) return;
  final colors = context.appColors;
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(tr('إبلاغ عن هذا المنشور'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.text)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(tr('اختر السبب الأقرب. لن يعرف صاحب المنشور أنك من أبلغ.'),
                  style: TextStyle(fontSize: 12, color: colors.textDim)),
            ),
          ),
          for (final reason in SocialService.reportReasons.entries)
            ListTile(
              title: Text(tr(reason.value)),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await SocialService.reportPost(
                      post.id, post.uid, reason.key);
                  messenger.showSnackBar(SnackBar(
                      content: Text(tr('تم إرسال البلاغ، شكراً لك'))));
                  await PostService.hidePost(post.id);
                } catch (error) {
                  messenger.showSnackBar(
                      SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر إرسال البلاغ')))));
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// أيقونة مشاركة بشكل الطائرة الورقية (مثل إنستغرام)، لا تنعكس في الواجهة العربية.
class _SharePlaneIcon extends StatelessWidget {
  const _SharePlaneIcon();

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Transform.rotate(
          angle: -0.38,
          child: Icon(Icons.send_outlined,
              size: 26, color: context.appColors.text),
        ),
      );
}

/// نص منشور تُلوَّن فيه الهاشتاقات والروابط وتُفتح عند النقر:
/// الهاشتاق يفتح البحث عنه، والرابط (http/https أو www) يفتح في المتصفح.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? leading; // مثل اسم صاحب المنشور قبل الوصف
  final VoidCallback? onLeadingTap;
  /// عدد الأسطر قبل الاقتطاع مع زر «المزيد/أقل» (null = عرض النص كاملاً).
  final int? collapsedLines;
  const LinkText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.leading,
    this.onLeadingTap,
    this.collapsedLines,
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
  bool _expanded = false;

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
        messenger.showSnackBar(SnackBar(content: Text(tr('تعذر فتح الرابط'))));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذر فتح الرابط'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    // أزرق للروابط والهاشتاقات (أفتح قليلاً في الوضع الداكن ليُقرأ بوضوح).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linkColor =
        isDark ? const Color(0xFF4DA3FF) : const Color(0xFF1A73E8);
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
    final span = TextSpan(style: widget.style, children: spans);
    final limit = widget.collapsedLines;
    if (limit == null) return Text.rich(span, textAlign: widget.textAlign);
    return LayoutBuilder(builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(
            style: DefaultTextStyle.of(context).style.merge(widget.style),
            children: spans),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: limit,
      )..layout(maxWidth: c.maxWidth);
      final overflows = painter.didExceedMaxLines;
      painter.dispose();
      if (!overflows) return Text.rich(span, textAlign: widget.textAlign);
      final centered = widget.textAlign == TextAlign.center;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text.rich(
            span,
            textAlign: widget.textAlign,
            maxLines: _expanded ? null : limit,
            overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                _expanded ? tr('أقل') : tr('المزيد'),
                style: TextStyle(
                    color: context.appColors.textDim,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// مشغّل الفيديو داخل التطبيق (يوتيوب وغيره). نعرض الغلاف أولاً (خفيف على الصفحة
/// الرئيسية) وعند النقر يبدأ الفيديو في مكانه دون الخروج من التطبيق.
class VideoInline extends StatefulWidget {
  final VideoSource source;
  final bool autoPlay;
  const VideoInline({super.key, required this.source, this.autoPlay = false});

  @override
  State<VideoInline> createState() => _VideoInlineState();
}

/// المشغّل المضمّن النشط حالياً (تغييره يغلق أي مشغّل آخر).
final ValueNotifier<Object?> activeInlineVideo = ValueNotifier<Object?>(null);

/// يغلق أي فيديو مضمّن يعمل الآن (يُستدعى قبل فتح نافذة شورتز).
void stopInlineVideos() => activeInlineVideo.value = Object();

class _VideoInlineState extends State<VideoInline> {
  /// المشغّل الوحيد النشط حالياً: تشغيل فيديو جديد يغلق السابق.
  static final ValueNotifier<Object?> _active = activeInlineVideo;
  double get _aspect => widget.source.aspect;

  late bool _playing = widget.autoPlay;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    _active.addListener(_onActiveChanged);
    if (_playing) _claim();
  }

  void _claim() {
    _active.value = this;
    // أثناء التشغيل: إذا خرج الفيديو من الشاشة (تمرير) يُغلق ويتوقف صوته.
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted || !_playing) return;
      // صفحة أخرى فُتحت فوق هذا المنشور (ملف شخصي، منشور...): نوقف الفيديو.
      final secondary = ModalRoute.of(context)?.secondaryAnimation;
      if (secondary != null && secondary.status != AnimationStatus.dismissed) {
        _stop();
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final screenH = MediaQuery.of(context).size.height;
      final visible = (bottom.clamp(0, screenH) - top.clamp(0, screenH));
      if (visible < box.size.height * 0.3) _stop();
    });
  }

  void _stop() {
    _watch?.cancel();
    _watch = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  void _onActiveChanged() {
    if (_active.value != this) _stop();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _active.removeListener(_onActiveChanged);
    if (_active.value == this) _active.value = null;
    super.dispose();
  }

  /// يحدّ ارتفاع الفيديو (16:9) بنحو 55% من ارتفاع الشاشة، فلا يملأ الشاشة
  /// على الكمبيوتر ويبقى ما تحته قابلاً للتمرير.
  Widget _limit(BuildContext context, Widget child) {
    final maxH = MediaQuery.of(context).size.height *
        (widget.source.isShort ? 0.7 : 0.55);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxH * _aspect),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // التشغيل داخل التطبيق فقط: لا يوجد رابط «فتح في المنصة».
    return _limit(
        context,
        _playing
            ? buildVideoEmbed(widget.source, aspect: _aspect)
            : _thumb(context));
  }

  Widget _thumb(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _playing = true);
        _claim();
      },
      child: AspectRatio(
        aspectRatio: _aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            VideoCover(source: widget.source),
            Align(
              // مع الغلاف المرسوم يكون الاسم في الأعلى، فتنزل الأيقونة قليلاً.
              alignment: widget.source.thumbUrl == null
                  ? const Alignment(0, 0.45)
                  : Alignment.center,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: widget.source.provider == VideoProvider.youtube
                        ? const Color(0xCCFF0000)
                        : const Color(0xB3000000),
                    shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ],
        ),
      ),
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
      appBar: AppBar(title: Text(tr('المنشور'))),
      body: SafeArea(
        child: StreamBuilder<Post?>(
          stream: PostService.postStream(post.id),
          initialData: post,
          builder: (context, snap) {
            final live = snap.data;
            if (live == null) {
              return Center(child: Text(tr('هذا المنشور لم يعد متاحاً')));
            }
            return ListView(
                children: [
                  PostCard(post: live, autoPlayVideo: true, expandText: true)
                ]);
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

  /// رابط صورة محدد (لصفحات الألبوم)؛ وإلا تُعرض الصورة الأولى للمنشور.
  final String? urlOverride;

  /// يُستدعى مرة بعد ظهور الصورة فعلاً (أو فشل تحميلها)؛ يستخدمه عارض القصص
  /// ليبدأ عدّاد المدة بعد التحميل لا قبله.
  final VoidCallback? onLoaded;
  const PostImage(
      {super.key,
      required this.post,
      this.fit = BoxFit.cover,
      this.height,
      this.urlOverride,
      this.onLoaded});

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
            Text(tr('تعذر تحميل الصورة'),
                style:
                    TextStyle(color: context.appColors.textDim, fontSize: 12)),
          ],
        ),
      ),
    );
    final url = urlOverride ?? post.mediaUrl;
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: PostService.optimizedImageUrl(url, decodeWidth),
        width: double.infinity,
        height: height,
        fit: fit,
        memCacheWidth: decodeWidth,
        placeholder: (_, __) => loading,
        imageBuilder: onLoaded == null
            ? null
            : (_, provider) {
                _notifyLoaded();
                return Image(
                    image: provider,
                    width: double.infinity,
                    height: height,
                    fit: fit);
              },
        errorWidget: (_, __, ___) {
          _notifyLoaded();
          return broken;
        },
      );
    }
    if (post.mediaId == null) {
      _notifyLoaded();
      return broken;
    }
    return FutureBuilder<Uint8List>(
      future: PostService.mediaBytes(post),
      builder: (_, s) {
        if (s.hasError) {
          _notifyLoaded();
          return broken;
        }
        if (!s.hasData) return loading;
        _notifyLoaded();
        return Image.memory(s.data!,
            width: double.infinity,
            height: height,
            fit: fit,
            cacheWidth: decodeWidth,
            gaplessPlayback: true);
      },
    );
  }

  void _notifyLoaded() {
    final cb = onLoaded;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
  }
}


/// ألبوم صور: تمرير أفقي بين صور المنشور مع عدّاد (1/5) ونقاط الصفحات.
class PostAlbumPager extends StatefulWidget {
  final Post post;
  final double height;
  const PostAlbumPager({super.key, required this.post, required this.height});

  @override
  State<PostAlbumPager> createState() => _PostAlbumPagerState();
}

class _PostAlbumPagerState extends State<PostAlbumPager> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.post.imageUrls;
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => PostImage(
            post: widget.post,
            urlOverride: urls[i],
            fit: BoxFit.contain,
            height: widget.height,
          ),
        ),
        PositionedDirectional(
          top: 10,
          end: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_page + 1}/${urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < urls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _page ? 8 : 6,
                    height: i == _page ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? Colors.white : Colors.white54,
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 3)
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// شريط أفقي لبطاقات شورتز (9:16). الضغط على بطاقة يفتح الفيديو في نافذة عمودية.
class ShortsRow extends StatelessWidget {
  final List<Post> shorts;
  final bool fromProfile; // في الملف الشخصي تظهر خيارات التعديل والحذف لصاحبه
  final EdgeInsetsGeometry padding;
  const ShortsRow(
      {super.key,
      required this.shorts,
      this.fromProfile = false,
      this.padding = const EdgeInsets.symmetric(vertical: 10)});

  @override
  Widget build(BuildContext context) {
    if (shorts.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text('Shorts',
                style: TextStyle(
                    color: colors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 250,
            child: ScrollConfiguration(
              // السحب بالماوس على الكمبيوتر.
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: shorts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _ShortCard(
                    post: shorts[i], shorts: shorts, fromProfile: fromProfile),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortCard extends StatelessWidget {
  final Post post;
  final List<Post> shorts;
  final bool fromProfile;
  const _ShortCard(
      {required this.post, required this.shorts, this.fromProfile = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showShortDialog(context, post,
          fromProfile: fromProfile, shorts: shorts),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              if (post.video != null) VideoCover(source: post.video!),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xAA000000)],
                  ),
                ),
              ),
              const Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 40),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  post.caption.isNotEmpty ? post.caption : post.username,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// يفتح عارض شورتز العمودي: تمرير/أسهم/مفاتيح للانتقال بين الفيديوهات.
void showShortDialog(BuildContext context, Post post,
    {bool fromProfile = false, List<Post>? shorts}) {
  stopInlineVideos();
  final list = (shorts == null || shorts.isEmpty) ? [post] : shorts;
  final i = list.indexWhere((p) => p.id == post.id);
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ShortsViewer(
        shorts: list, initialIndex: i < 0 ? 0 : i, fromProfile: fromProfile),
  ));
}

/// كل الشورتز تُعرض بتصميم تيك توك: فيديو بملء الشاشة وأزرار على اليسار.
/// الملف المرفوع على التطبيق يبقى يعمل أثناء فتح القوائم؛ مشغّل الويب
/// ويوتيوب (iframe/WebView) يُزال لحظياً لأنه يلتقط النقرات فوقه.
bool _keepsPlayingUnderMenu(Post p) =>
    !kIsWeb && p.video?.provider == VideoProvider.file;

class ShortsViewer extends StatefulWidget {
  final List<Post> shorts;
  final int initialIndex;
  final bool fromProfile;
  const ShortsViewer(
      {super.key,
      required this.shorts,
      required this.initialIndex,
      this.fromProfile = false});

  @override
  State<ShortsViewer> createState() => _ShortsViewerState();
}

class _ShortsViewerState extends State<ShortsViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  // أثناء فتح القائمة نخفي مشغّل يوتيوب (iframe) لأنه يلتقط النقرات فوقه في الويب.
  bool _menuOpen = false;
  Timer? _viewTimer;

  @override
  void initState() {
    super.initState();
    _scheduleView();
  }

  /// تسجيل مشاهدة المقطع الحالي بعد بقائه لحظة على الشاشة.
  void _scheduleView() {
    _viewTimer?.cancel();
    if (widget.shorts.isEmpty) return;
    final p = widget.shorts[_current.clamp(0, widget.shorts.length - 1)];
    _viewTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) PostService.recordPostView(p);
    });
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    // تحديد السرعة حتى لا يقفز عدة فيديوهات بحركة عجلة واحدة.
    final now = DateTime.now();
    if (now.difference(_lastMove).inMilliseconds < 450) return;
    final next = (_current + delta).clamp(0, widget.shorts.length - 1);
    if (next == _current) return;
    _lastMove = now;
    setState(() => _current = next);
    _scheduleView();
    _pages.animateToPage(next,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// فتح التعليقات/المشاركة: نُزيل مشغّل يوتيوب أولاً (iframe يلتقط النقرات)،
  /// ويعود الفيديو بعد إغلاق النافذة.
  Future<void> _overlay(Future<void> Function() open) async {
    setState(() => _menuOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await open();
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  void _onMenu(String v, Post post) async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final messenger = ScaffoldMessenger.of(context);
    switch (v) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: PostService.postLink(post)));
        unawaited(PostService.registerShare(post.id));
        messenger.showSnackBar(SnackBar(content: Text(tr('تم نسخ الرابط'))));
      case 'share':
        Navigator.of(context).pop();
        showPostShareSheet(rootCtx, post);
      case 'story':
        Navigator.of(context).pop();
        showAddToStoryDialog(rootCtx, post, messenger);
      case 'edit':
        Navigator.of(context).pop();
        _editShortCaption(rootCtx, post, messenger);
      case 'delete':
        // نُزيل مشغّل يوتيوب (iframe) قبل الحوار وإلا التقط نقرة «حذف».
        setState(() => _menuOpen = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final deleted = await _confirmDeleteShort(context, post);
        if (!deleted && mounted) setState(() => _menuOpen = false);
    }
  }

  Widget _page(Post post, bool active, int index) {
    return TikTokShortPage(
      key: ValueKey('tt-${post.id}'),
      post: post,
      active: active,
      onComments: () => _overlay(() => showCommentsSheet(context, post)),
      onShare: () => _overlay(() => showPostShareSheet(
          Navigator.of(context, rootNavigator: true).context, post)),
      onNext: () => _go(1),
      onPrev: () => _go(-1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.shorts[_current];
    final mine = post.uid == PostService.uidOrEmpty;
    final topInset = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
            _go(1);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
            _go(-1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _go(e.scrollDelta.dy > 0 ? 1 : -1);
          },
          // بلا SafeArea: الفيديو يملأ الشاشة كاملة (تحت شريط الحالة) مثل تيك توك.
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pages,
                  scrollDirection: Axis.vertical,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.shorts.length,
                  itemBuilder: (_, i) => _page(
                      widget.shorts[i],
                      i == _current &&
                          (!_menuOpen || _keepsPlayingUnderMenu(widget.shorts[i])),
                      i),
                ),
              ),
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                height: 56,
                child: Row(
                  children: [
                    PointerInterceptor(
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 8, color: Colors.black87)
                            ]),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const Spacer(),
                    PointerInterceptor(
                      child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black87)
                          ]),
                      onOpened: () => setState(() => _menuOpen = true),
                      onCanceled: () => setState(() => _menuOpen = false),
                      onSelected: (v) {
                        setState(() => _menuOpen = false);
                        _onMenu(v, post);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'copy', child: Text(tr('نسخ الرابط'))),
                        PopupMenuItem(
                            value: 'share', child: Text(tr('مشاركة'))),
                        PopupMenuItem(
                            value: 'story', child: Text(tr('إضافة إلى القصة'))),
                        if (widget.fromProfile && mine)
                          PopupMenuItem(
                              value: 'edit', child: Text(tr('تعديل الوصف'))),
                        if (widget.fromProfile && mine)
                          PopupMenuItem(
                              value: 'delete', child: Text(tr('حذف'))),
                      ],
                    ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تأكيد ثم حذف شورتز من نافذة المعاينة (لصاحبه فقط).
Future<bool> _confirmDeleteShort(BuildContext dialogCtx, Post post) async {
  final messenger = ScaffoldMessenger.of(dialogCtx);
  final ok = await showDialog<bool>(
    context: dialogCtx,
    builder: (ctx) => AlertDialog(
      title: Text(tr('حذف الفيديو؟')),
      content: Text(tr('لا يمكن التراجع عن هذا الإجراء.')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إلغاء'))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('حذف'))),
      ],
    ),
  );
  if (ok != true) return false;
  // نغلق نافذة الفيديو أولاً فيتوقف الصوت ثم نحذف.
  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
  try {
    await PostService.deletePost(post);
    messenger.showSnackBar(SnackBar(content: Text(tr('تم حذف الفيديو'))));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر الحذف')))));
  }
  return true;
}

/// تعديل وصف شورتز (من الملف الشخصي لصاحبه) بنفس الحوار الواسع.
Future<void> _editShortCaption(
        BuildContext rootCtx, Post post, ScaffoldMessengerState messenger) =>
    editPostCaption(rootCtx, post);

/// يوقف أي فيديو يوتيوب مضمّن ويمنحه إطاراً ليُزال من الشاشة؛ مشغّل الويب
/// (iframe) يبقى فوق الواجهة ويلتقط النقرات، فنزيله قبل فتح أي حوار.
Future<void> _releaseVideosForDialog() async {
  stopInlineVideos();
  await WidgetsBinding.instance.endOfFrame;
}

/// حوار تعديل واسع لنص المنشور أو وصف الصورة/الفيديو (للمالك فقط).
Future<void> editPostCaption(BuildContext context, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  final rootCtx = Navigator.of(context, rootNavigator: true).context;
  final isText = post.type == PostType.text;
  await _releaseVideosForDialog();
  if (!rootCtx.mounted) return;
  final result = await showDialog<_EditResult>(
    context: rootCtx,
    barrierDismissible: false,
    builder: (_) => _EditCaptionDialog(
        initial: post.caption,
        isText: isText,
        canStyle: isText && !post.hasVideo,
        tbg: post.tbg,
        tc: post.tc),
  );
  if (result == null) return;
  final caption = result.caption;
  final styleChanged = result.tbg != post.tbg || result.tc != post.tc;
  if (caption == post.caption && !styleChanged && result.images.isEmpty) {
    return;
  }
  if (isText && !post.hasVideo && caption.isEmpty && result.images.isEmpty) {
    messenger.showSnackBar(
        SnackBar(content: Text(tr('لا يمكن ترك المنشور فارغاً'))));
    return;
  }
  try {
    if (result.images.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
          duration: const Duration(minutes: 2),
          content: Text(tr('جارٍ رفع الصور...'))));
      await PostService.convertTextToPhotoPost(post,
          caption: caption,
          images: [for (final img in result.images) img.bytes],
          mime: 'image/jpeg',
          ext: 'jpg');
      messenger.hideCurrentSnackBar();
    } else if (isText) {
      await PostService.updateTextPost(post,
          caption: caption, tbg: result.tbg, tc: result.tc);
    } else {
      await PostService.updateCaption(post, caption);
    }
    messenger.showSnackBar(SnackBar(
        content: Text(trf('تم تعديل {0}', [isText ? tr('المنشور') : tr('الوصف')]))));
  } catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر التعديل')))));
  }
}

/// تأكيد ثم حذف المنشور (للمالك فقط).
Future<void> deletePostWithConfirm(BuildContext context, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  final rootCtx = Navigator.of(context, rootNavigator: true).context;
  await _releaseVideosForDialog();
  if (!rootCtx.mounted) return;
  final ok = await showDialog<bool>(
    context: rootCtx,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(tr('حذف المنشور؟')),
      content: Text(tr('لا يمكن التراجع عن هذا الإجراء.')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إلغاء'))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('حذف'))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await PostService.deletePost(post);
    messenger.showSnackBar(SnackBar(content: Text(tr('تم حذف المنشور'))));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر الحذف')))));
  }
}

/// نتيجة حوار التعديل: النص، وخلفية ولون المنشور النصي، والصور المضافة.
class _EditResult {
  final String caption;
  final int? tbg;
  final int? tc;
  final List<PickedMedia> images;
  const _EditResult(this.caption, this.tbg, this.tc, this.images);
}

class _EditCaptionDialog extends StatefulWidget {
  final String initial;
  final bool isText;
  final bool canStyle; // منشور نصي بلا فيديو: خلفية ولون وإضافة صور
  final int? tbg;
  final int? tc;
  const _EditCaptionDialog({
    required this.initial,
    required this.isText,
    this.canStyle = false,
    this.tbg,
    this.tc,
  });

  @override
  State<_EditCaptionDialog> createState() => _EditCaptionDialogState();
}

class _EditCaptionDialogState extends State<_EditCaptionDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  late int? _tbg = widget.tbg;
  late int? _tc = widget.tc;
  final List<PickedMedia> _images = [];
  final _picker = ImagePicker();
  String? _error;

  bool get _styled =>
      widget.canStyle && _images.isEmpty && postBgGradient(_tbg) != null;

  Future<void> _addPhotos() async {
    try {
      final room = PostService.maxAlbumImages - _images.length;
      final (picked, truncated) = await pickAlbumMedia(_picker, max: room);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _images.addAll(picked);
        _error = truncated
            ? trf('الحد الأقصى {0} صور', [PostService.maxAlbumImages])
            : null;
      });
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('تعذر اختيار الصور'));
    }
  }

  Widget _photosRow(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_images.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_images[i].bytes,
                        width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 9,
                        backgroundColor: Colors.black54,
                        child:
                            Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_images.length < PostService.maxAlbumImages)
          TextButton.icon(
            onPressed: _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_images.isEmpty ? tr('إضافة صور') : tr('إضافة المزيد')),
          ),
        if (_images.isNotEmpty)
          Text(tr('سيتحوّل المنشور إلى منشور صور وتُزال الخلفية الملونة'),
              style: TextStyle(fontSize: 12, color: colors.textDim)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: colors.text)),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          minWidth: size.width > 800 ? 600 : size.width - 24,
          maxHeight: size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isText ? tr('تعديل المنشور') : tr('تعديل الوصف'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: _styled
                            ? BoxDecoration(
                                gradient: postBgGradient(_tbg),
                                borderRadius: BorderRadius.circular(14))
                            : null,
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          maxLength: 500,
                          minLines: _styled ? 6 : 8,
                          maxLines: 16,
                          keyboardType: TextInputType.multiline,
                          textAlign:
                              _styled ? TextAlign.center : TextAlign.start,
                          style: widget.canStyle &&
                                  (_styled || postTextColor(_tc) != null)
                              ? TextStyle(
                                  color: postTextColor(_tc) ??
                                      (_styled ? Colors.white : null),
                                  fontSize: _styled ? 22 : null,
                                  fontWeight:
                                      _styled ? FontWeight.w800 : null)
                              : null,
                          decoration: InputDecoration(
                            hintText: widget.isText
                                ? tr('اكتب المنشور...')
                                : tr('اكتب وصفاً...'),
                            hintStyle: _styled
                                ? const TextStyle(color: Colors.white70)
                                : null,
                            filled: _styled ? false : null,
                            counterStyle: _styled
                                ? const TextStyle(color: Colors.white70)
                                : null,
                            border: _styled
                                ? InputBorder.none
                                : OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14)),
                            enabledBorder: _styled ? InputBorder.none : null,
                            focusedBorder: _styled ? InputBorder.none : null,
                          ),
                        ),
                      ),
                      if (widget.canStyle && _images.isEmpty)
                        PostStylePicker(
                          bg: _tbg,
                          textColor: _tc,
                          onBg: (v) => setState(() => _tbg = v),
                          onTextColor: (v) => setState(() => _tc = v),
                        ),
                      if (widget.canStyle && PostService.useRemoteMedia)
                        _photosRow(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('إلغاء'))),
                  const SizedBox(width: 8),
                  // الثيم العام يجعل FilledButton بعرض كامل (Size.fromHeight)،
                  // وداخل Row يختفي الزر؛ لذا نحدّد حداً أدنى بعرض محدود.
                  FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 44)),
                      onPressed: () => Navigator.pop(
                          context,
                          _EditResult(
                              _controller.text.trim(),
                              widget.canStyle && _images.isEmpty ? _tbg : null,
                              widget.canStyle && _images.isEmpty ? _tc : null,
                              List.of(_images))),
                      child: Text(tr('حفظ'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
