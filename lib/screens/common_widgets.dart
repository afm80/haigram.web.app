import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../services/presence_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'post_widgets.dart' show timeAgo;
import 'profile_screen.dart';
import '../route_state.dart';

const _commentStickers = [
  '🥰',
  '😂',
  '😍',
  '🥹',
  '👍',
  '👏',
  '🔥',
  '🥳',
  '🤍',
  '💯',
  '🎉',
  '😘',
];

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
                    : [AppColors.brandRed, AppColors.brandCyan],
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
void showCommentsSheet(BuildContext context, Post post) {
  showModalBottomSheet(
    context: context,
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
  bool _showStickers = false;

  void _insertSticker(String sticker) {
    final text = _text.text;
    final selection = _text.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length).toInt()
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length).toInt()
        : start;
    _text.value = TextEditingValue(
      text: text.replaceRange(start, end, sticker),
      selection: TextSelection.collapsed(offset: start + sticker.length),
    );
    setState(() => _showStickers = false);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await PostService.addComment(widget.post.id, t);
      _text.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر إرسال التعليق: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showCommentActions(Comment comment) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          title: const Text('حذف التعليق'),
          onTap: () async {
            Navigator.pop(sheetContext);
            try {
              await PostService.deleteComment(widget.post.id, comment.id);
            } catch (error) {
              if (widget.outerContext.mounted) {
                ScaffoldMessenger.of(widget.outerContext).showSnackBar(
                  SnackBar(content: Text('تعذر حذف التعليق: $error')),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    try {
      await PostService.toggleCommentLike(widget.post.id, comment.id);
    } catch (error) {
      if (widget.outerContext.mounted) {
        ScaffoldMessenger.of(widget.outerContext).showSnackBar(
          SnackBar(content: Text('تعذر الإعجاب بالتعليق: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final me = PostService.uidOrEmpty;
    return Padding(
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('التعليقات',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Divider(
                height: 1, color: context.appColors.text.withOpacity(0.12)),
            Expanded(
              child: StreamBuilder<List<Comment>>(
                stream: PostService.comments(widget.post.id),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                        child: Text('تعذر تحميل التعليقات\n${snap.error}',
                            textAlign: TextAlign.center));
                  }
                  if (!snap.hasData) {
                    return const AppLoading(message: 'جارٍ تحميل التعليقات...');
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.mode_comment_outlined,
                      title: 'لا توجد تعليقات بعد',
                      message: 'ابدأ المحادثة وكن أول من يعلّق.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final canDelete = c.uid == me || widget.post.uid == me;
                      void open() {
                        Navigator.pop(context);
                        openProfile(widget.outerContext, c.uid);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(
                                uid: c.uid,
                                fallbackName: c.username,
                                radius: 17,
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
                                    onLongPress: canDelete
                                        ? () => _showCommentActions(c)
                                        : null,
                                    child: Text(c.text,
                                        style: const TextStyle(height: 1.4)),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: c.likedBy.contains(me)
                                            ? 'إلغاء الإعجاب'
                                            : 'إعجاب بالتعليق',
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
                                              ? AppColors.videoLike
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
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_showStickers)
              SizedBox(
                height: 104,
                child: GridView.count(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  crossAxisCount: 6,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 8,
                  children: [
                    for (var i = 0; i < _commentStickers.length; i++)
                      InkWell(
                        onTap: () => _insertSticker(_commentStickers[i]),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: [
                              const Color(0xFFFFE0E8),
                              const Color(0xFFFFF0C2),
                              const Color(0xFFE4DBFF),
                              const Color(0xFFD8F5E8),
                            ][i % 4],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _commentStickers[i],
                            style: const TextStyle(fontSize: 25),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Divider(
                height: 1, color: context.appColors.text.withOpacity(0.12)),
            SafeArea(
              top: false,
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
                      tooltip: _showStickers ? 'إخفاء الملصقات' : 'الملصقات',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        setState(() => _showStickers = !_showStickers);
                      },
                      icon: Icon(
                        _showStickers
                            ? Icons.keyboard_rounded
                            : Icons.emoji_emotions_outlined,
                        color: AppColors.accent,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onTap: () {
                          if (_showStickers) {
                            setState(() => _showStickers = false);
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'أضف تعليقاً...',
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
