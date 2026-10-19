import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/post_service.dart';
import '../auth_gate.dart';
import '../services/presence_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'photo_tools.dart' show fitImageUnderLimit;
import 'post_widgets.dart' show timeAgo, stopInlineVideos;
import 'sticker_sheet.dart';
import 'translate_widgets.dart';
import 'profile_screen.dart';
import '../route_state.dart';

import '../l10n.dart';
import '../net_error.dart';
/// يفتح ملف مستخدم (مثل تيك توك / إنستغرام).
void openProfile(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  Navigator.of(context).push(appRoute(
      'user', {'uid': uid}, (_) => UserProfileScreen(uid: uid)));
}

/// صورة المستخدم: صورته إن وُجدت وإلا أول حرف من اسمه.
class UserAvatar extends StatelessWidget {
  final String uid;
  final String fallbackName;
  final double radius;
  final VoidCallback? onTap;
  final bool showOnline;
  final bool hasStory;
  final bool storySeen;
  final AppUser? profile;

  const UserAvatar(
      {super.key,
      required this.uid,
      this.fallbackName = '',
      this.radius = 20,
      this.onTap,
      this.showOnline = false,
      this.hasStory = false,
      this.storySeen = false,
      this.profile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: profile == null
          ? FutureBuilder<AppUser?>(
              future: UserService.profileOf(uid),
              builder: (context, snapshot) => _buildAvatar(
                context,
                snapshot.data,
              ),
            )
          : _buildAvatar(context, profile),
    );
  }

  Widget _buildAvatar(BuildContext context, AppUser? user) {
    final image = user?.avatarImage;
    final label = user != null
        ? user.initial
        : (fallbackName.isNotEmpty ? fallbackName[0].toUpperCase() : '?');
    final circle = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accent,
      backgroundImage: image,
      child: image == null
          ? Text(
              label,
              style: TextStyle(
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            )
          : null,
    );
    final avatar = hasStory
        ? Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: storySeen
                    ? [context.appColors.textDim, context.appColors.textDim]
                    : [AppColors.brandPurple, AppColors.brandOrange],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: circle,
          )
        : circle;
    if (!showOnline || uid.isEmpty) return avatar;
    return StreamBuilder<bool>(
      stream: PresenceService.isOnline(uid),
      builder: (context, presence) => Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (presence.data == true)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: radius * 0.48,
                height: radius * 0.48,
                decoration: BoxDecoration(
                  color: const Color(0xFF31C75A),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.appColors.bg,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// نافذة التعليقات السفلية.
Future<void> showCommentsSheet(BuildContext context, Post post) async {
  // مشغّل يوتيوب على الويب (iframe) يبقى فوق واجهة فلاتر ويلتقط النقرات،
  // فنوقف الفيديوهات المضمّنة وننتظر إطاراً ليُزال قبل فتح الورقة.
  stopInlineVideos();
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CommentsSheet(post: post, outerContext: context),
  );
}

class _CommentsSheet extends StatefulWidget {
  final Post post;
  final BuildContext outerContext;
  const _CommentsSheet({required this.post, required this.outerContext});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  final _picker = ImagePicker();
  Uint8List? _pendingImage; // صورة مرفقة بانتظار الإرسال اليدوي
  final _focus = FocusNode();
  bool _showStickers = false;
  Comment? _replyTo; // التعليق الذي نردّ عليه حالياً
  final Set<String> _expanded = {}; // التعليقات التي تُعرض ردودها

  @override
  void initState() {
    super.initState();
    _focus.addListener(_hideStickersOnFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_hideStickersOnFocus);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _fail(String what, Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error, fallback: what))));
    }
  }

  void _post(String text,
      {String kind = 'text',
      Uint8List? imageBytes,
      String? failure}) {
    if (needsLogin(context)) return;
    // الرد دائماً على التعليق الرئيسي (مستوى واحد)، مع ذكر من نردّ عليه.
    final target = _replyTo;
    final parentId = target == null ? null : (target.parentId ?? target.id);
    if (parentId != null) _expanded.add(parentId);
    PostService.addComment(
      widget.post.id,
      text,
      ownerUid: widget.post.uid,
      kind: kind,
      imageBytes: imageBytes,
      parentId: parentId,
      replyToUsername: target?.username,
    ).catchError((Object e) => _fail(failure ?? tr('تعذر إرسال التعليق'), e));
  }

  /// يرسل ما في خانة الكتابة (نص/ملصق) والصورة المرفقة عند ضغط زر الإرسال فقط.
  void _send() {
    if (needsLogin(context)) return;
    final t = _text.text.trim();
    final image = _pendingImage;
    if (t.isEmpty && image == null) return;
    _text.clear();
    setState(() => _pendingImage = null);
    if (image != null) {
      _post('📷 صورة',
          kind: 'image', imageBytes: image, failure: tr('تعذر إرسال الصورة'));
    }
    if (t.isNotEmpty) {
      _post(t, kind: isStickerOnly(t) ? 'sticker' : 'text');
    }
    if (_replyTo != null) setState(() => _replyTo = null);
  }

  Future<void> _pickImage() async {
    if (_sending || needsLogin(context)) return;
    setState(() => _sending = true);
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (image == null) return;
      final bytes = await fitImageUnderLimit(await image.readAsBytes());
      if (mounted) setState(() => _pendingImage = bytes);
    } catch (e) {
      _fail(tr('تعذر إرفاق الصورة'), e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showCommentActions(Comment comment,
      {required bool canDelete, required bool canReport}) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: context.appColors.text),
                title: Text(tr('حذف التعليق')),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await PostService.deleteComment(
                        widget.post.id, comment.id);
                  } catch (error) {
                    if (widget.outerContext.mounted) {
                      ScaffoldMessenger.of(widget.outerContext).showSnackBar(
                        SnackBar(
                            content: Text(friendlyError(error,
                                fallback: tr('تعذر حذف التعليق')))),
                      );
                    }
                  }
                },
              ),
            if (canReport)
              ListTile(
                leading: Icon(Icons.flag_outlined,
                    color: context.appColors.text),
                title: Text(tr('إبلاغ عن التعليق')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportComment(comment);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// نافذة أسباب الإبلاغ عن تعليق.
  Future<void> _reportComment(Comment comment) async {
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(widget.outerContext);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
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
                child: Text(tr('إبلاغ عن هذا التعليق'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.text)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                    tr('اختر السبب الأقرب. لن يعرف صاحب التعليق أنك من أبلغ.'),
                    style: TextStyle(
                        fontSize: 12, color: context.appColors.textDim)),
              ),
            ),
            for (final reason in SocialService.reportReasons.entries)
              ListTile(
                title: Text(tr(reason.value)),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await SocialService.reportComment(widget.post.id,
                        comment.id, comment.uid, reason.key);
                    messenger.showSnackBar(SnackBar(
                        content: Text(tr('تم إرسال البلاغ، شكراً لك'))));
                  } catch (error) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(friendlyError(error,
                            fallback: tr('تعذر إرسال البلاغ')))));
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    if (needsLogin(context)) return;
    try {
      await PostService.toggleCommentLike(widget.post.id, comment.id);
    } catch (error) {
      if (widget.outerContext.mounted) {
        ScaffoldMessenger.of(widget.outerContext).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر الإعجاب بالتعليق')))),
        );
      }
    }
  }

  /// صف تعليق واحد (تعليق رئيسي أو رد).
  Widget _commentRow(Comment c, String me, {bool isReply = false}) {
                                            final canDelete = c.uid == me || widget.post.uid == me;
                      final canReport = c.uid != me;
                      void open() {
                        Navigator.pop(context);
                        openProfile(widget.outerContext, c.uid);
                      }

                      return Padding(
                        padding: isReply
                            ? const EdgeInsetsDirectional.only(
                                start: 62, end: 14, top: 6, bottom: 6)
                            : const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(
                                uid: c.uid,
                                fallbackName: c.username,
                                radius: isReply ? 13 : 17,
                                onTap: open),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: open,
                                    child: Row(
                                      children: [
                                        Flexible(
                                            child: Text(c.username,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13))),
                                        const SizedBox(width: 8),
                                        Text(timeAgo(c.createdAt),
                                            style: TextStyle(
                                                color: context.appColors.textDim,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  GestureDetector(
                                    onLongPress: (canDelete || canReport)
                                        ? () => _showCommentActions(c,
                                            canDelete: canDelete,
                                            canReport: canReport)
                                        : null,
                                    child: c.kind == 'image' &&
                                            c.imageBytes != null
                                        ? GestureDetector(
                                            onTap: () => openFullScreenImage(
                                                context, c.imageBytes!),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.memory(
                                                c.imageBytes!,
                                                width: 180,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          )
                                        : c.kind == 'sticker'
                                            ? StickerMessage(c.text, base: 44)
                                            : TranslatableText(
                                                text: c.text,
                                                builder: (shown) => Text.rich(
                                                  TextSpan(children: [
                                                    if (isReply &&
                                                        (c.replyToUsername ??
                                                                '')
                                                            .isNotEmpty)
                                                      TextSpan(
                                                        text:
                                                            '@${c.replyToUsername} ',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700),
                                                      ),
                                                    ...inlineEmojiSpans(
                                                        shown,
                                                        const TextStyle(
                                                            height: 1.4)),
                                                  ]),
                                                  style: const TextStyle(
                                                    height: 1.4,
                                                    fontSize: null,
                                                  ),
                                                ),
                                              ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: c.likedBy.contains(me)
                                            ? tr('إلغاء الإعجاب')
                                            : tr('إعجاب بالتعليق'),
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(
                                            minWidth: 36, minHeight: 32),
                                        padding: EdgeInsets.zero,
                                        onPressed: () =>
                                            _toggleCommentLike(c),
                                        icon: Icon(
                                          c.likedBy.contains(me)
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          size: 18,
                                          color: c.likedBy.contains(me)
                                              ? AppColors.likeRed
                                              : context.appColors.textDim,
                                        ),
                                      ),
                                      if (c.likedBy.isNotEmpty)
                                        Text(
                                          '${c.likedBy.length}',
                                          style: TextStyle(
                                            color: context.appColors.textDim,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _startReply(c),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 8),
                                          child: Text(
                                            tr('رد'),
                                            style: TextStyle(
                                              color: context.appColors.textDim,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
  }

  /// يجمع الردود تحت التعليق الأب، مع زر «عرض/إخفاء الردود».
  Widget _buildList(List<Comment> list, String me) {
    final ids = {for (final c in list) c.id};
    final replies = <String, List<Comment>>{};
    final top = <Comment>[];
    for (final c in list) {
      final parent = c.parentId;
      if (parent == null || parent.isEmpty) {
        top.add(c);
      } else if (ids.contains(parent)) {
        (replies[parent] ??= <Comment>[]).add(c);
      }
    }
    final rows = <Widget>[];
    for (final c in top) {
      rows.add(_commentRow(c, me));
      final rs = replies[c.id] ?? const <Comment>[];
      if (rs.isEmpty) continue;
      final open = _expanded.contains(c.id);
      rows.add(Padding(
        padding: const EdgeInsetsDirectional.only(start: 62, bottom: 4),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(c.id);
              } else {
                _expanded.add(c.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                open ? tr('إخفاء الردود') : trf('عرض {0} ردود', [rs.length]),
                style: TextStyle(
                    color: context.appColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ));
      if (open) {
        for (final reply in rs) {
          rows.add(_commentRow(reply, me, isReply: true));
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: rows,
    );
  }

  void _startReply(Comment c) {
    if (needsLogin(context)) return;
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  void _toggleStickers() {
    if (_showStickers) {
      setState(() => _showStickers = false);
      _focus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _showStickers = true);
    }
  }

  /// عند الضغط على خانة الكتابة تُغلق لوحة الملصقات ويظهر الكيبورد.
  void _hideStickersOnFocus() {
    if (_focus.hasFocus && _showStickers && mounted) {
      setState(() => _showStickers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final me = PostService.uidOrEmpty;
    return PopScope(
        canPop: !_showStickers,
        onPopInvoked: (didPop) {
          if (!didPop) setState(() => _showStickers = false);
        },
        child: Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: context.appColors.textDim,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('التعليقات'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Divider(
                height: 1, color: context.appColors.text.withOpacity(0.12)),
            Expanded(
              child: StreamBuilder<List<Comment>>(
                stream: PostService.comments(widget.post.id),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorState(
                        error: snap.error,
                        title: tr('تعذر تحميل التعليقات'),
                        onRetry: () => setState(() {}));
                  }
                  if (!snap.hasData) {
                    return AppLoading(message: tr('جارٍ تحميل التعليقات...'));
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.mode_comment_outlined,
                      title: tr('لا توجد تعليقات بعد'),
                      message: tr('ابدأ المحادثة وكن أول من يعلّق.'),
                    );
                  }
                  return _buildList(list, me);
                },
              ),
            ),
            if (_pendingImage != null)
              PendingImagePreview(
                bytes: _pendingImage!,
                onRemove: () => setState(() => _pendingImage = null),
              ),
            if (_replyTo != null)
              Container(
                width: double.infinity,
                color: context.appColors.text.withOpacity(0.06),
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        trf('الرد على {0}', [_replyTo!.username]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.appColors.textDim, fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _replyTo = null),
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: context.appColors.textDim),
                    ),
                  ],
                ),
              ),
            Divider(
                height: 1, color: context.appColors.text.withOpacity(0.12)),
            SafeArea(
              top: false,
              bottom: !_showStickers,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    UserAvatar(
                        uid: me,
                        fallbackName: PostService.username,
                        radius: 17),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: tr('الملصقات'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (needsLogin(context)) return;
                        _toggleStickers();
                      },
                      icon: Icon(
                          _showStickers
                              ? Icons.keyboard_alt_outlined
                              : Icons.emoji_emotions_outlined,
                          color: context.appColors.text),
                    ),
                    IconButton(
                      tooltip: tr('إرسال صورة'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _sending ? null : _pickImage,
                      icon: Icon(Icons.image_outlined,
                          color: context.appColors.text),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        readOnly: !isLoggedIn,
                        onTap: () {
                          if (!isLoggedIn) needsLogin(context);
                        },
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: _replyTo != null
                              ? tr('أضف رداً...')
                              : tr('أضف تعليقاً...'),
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _send,
                      icon: Icon(Icons.send_rounded,
                          color: context.appColors.text),
                    ),
                  ],
                ),
              ),
            ),
            if (_showStickers)
              SafeArea(
                top: false,
                child: StickerPanel(controller: _text, height: 240),
              ),
          ],
        ),
      ),
    ));
  }
}


/// يبني زر الإعجاب بحالة فورية (تفاؤلية) وعدّاد حيّ:
/// يتغير اللون والعدد لحظة الضغط دون انتظار الشبكة، ويتراجع عند الفشل.
class LikeBuilder extends StatefulWidget {
  final Post post;
  final Widget Function(
      BuildContext context, bool liked, int count, VoidCallback toggle) builder;
  const LikeBuilder({super.key, required this.post, required this.builder});

  @override
  State<LikeBuilder> createState() => _LikeBuilderState();
}

class _LikeBuilderState extends State<LikeBuilder> {
  late final Stream<bool> _likedStream = PostService.isLiked(widget.post.id);
  bool? _override; // الحالة المتوقعة حتى يؤكدها الخادم
  bool _busy = false;

  // العدد يأتي من المنشور نفسه (القائمة الأم تحدّثه)، بدل اشتراك حيّ إضافي
  // على مستند كل فيديو. هذا التعديل المحلي يُصفَّر حين يصل عدد جديد من الخادم.
  int _delta = 0;

  @override
  void didUpdateWidget(covariant LikeBuilder old) {
    super.didUpdateWidget(old);
    if (old.post.likes != widget.post.likes) _delta = 0;
  }

  Future<void> _toggle(bool currentLiked) async {
    if (_busy || needsLogin(context)) return;
    _busy = true;
    final change = currentLiked ? -1 : 1;
    setState(() {
      _override = !currentLiked;
      _delta += change;
    });
    try {
      await PostService.toggleLike(widget.post.id, currentLiked);
    } catch (error) {
      if (mounted) {
        setState(() {
          _override = null;
          _delta -= change;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: tr('تعذر تسجيل الإعجاب')))),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _likedStream,
      builder: (context, likedSnap) {
        final serverLiked = likedSnap.data ?? false;
        if (_override != null && _override == serverLiked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _override == serverLiked) {
              setState(() => _override = null);
            }
          });
        }
        final liked = _override ?? serverLiked;
        var count = widget.post.likes + _delta;
        if (count < 0) count = 0;
        return widget.builder(context, liked, count, () => _toggle(liked));
      },
    );
  }
}

/// يفتح الصورة بملء الشاشة (تكبير بالقرص، إغلاق بالنقر أو زر ✕).
void openFullScreenImage(BuildContext context, Uint8List bytes) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FullScreenImageViewer(bytes: bytes),
    ),
  );
}

class FullScreenImageViewer extends StatelessWidget {
  final Uint8List bytes;
  const FullScreenImageViewer({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: tr('إغلاق'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SizedBox.expand(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }
}

/// معاينة صورة مرفقة داخل شريط الكتابة مع زر إزالة، قبل الإرسال اليدوي.
class PendingImagePreview extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const PendingImagePreview(
      {super.key, required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      alignment: AlignmentDirectional.centerStart,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, height: 90, fit: BoxFit.cover),
          ),
          PositionedDirectional(
            top: -6,
            end: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.black87, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
