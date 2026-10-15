import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// رابط مشاركة المنشور (?p=).
String postShareLink(Post post) => PostService.postLink(post);

/// ورقة المشاركة بنمط تيك توك: صف أصدقاء أعلى (تحديد متعدد + رسالة + إرسال)،
/// ثم صف تطبيقات المشاركة، ثم صف إجراءات (قصتي، حفظ، تنزيل...).
/// تُستخدم للمنشورات.
Future<void> showPostShareSheet(BuildContext context, Post post) {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.appColors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _PostShareSheet(post: post, messenger: messenger),
  );
}

class _PostShareSheet extends StatefulWidget {
  final Post post;
  final ScaffoldMessengerState messenger;
  const _PostShareSheet({required this.post, required this.messenger});

  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  late final Future<List<AppUser>> _friends = _loadFriends();
  final Map<String, AppUser> _selected = {};
  final _note = TextEditingController();
  bool _sending = false;

  Post get _post => widget.post;
  String get _noun => 'المنشور';
  String get _link => postShareLink(_post);

  String get _shareText {
    final caption = _post.caption.trim();
    final intro = 'شاهد هذا المنشور من @${_post.username} على Haigram';
    return [if (caption.isNotEmpty) caption, intro, _link].join('\n');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<List<AppUser>> _loadFriends() async {
    final ids = await SocialService.mutualFriendIds();
    final users = await Future.wait(ids.map(UserService.profileOf));
    return users.whereType<AppUser>().toList();
  }

  void _toast(String message) {
    widget.messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// يغلق الورقة ثم ينفّذ الإجراء ويعرض النتيجة (كما في تيك توك).
  void _runAndClose(Future<void> Function() action, String success) {
    Navigator.pop(context);
    unawaited(() async {
      try {
        await action();
        _toast(success);
      } catch (error) {
        _toast('تعذر تنفيذ العملية: $error');
      }
    }());
  }

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    setState(() => _sending = true);
    final note = _note.text.trim();
    final text = [if (note.isNotEmpty) note, _shareText].join('\n');
    final friends = _selected.values.toList();
    var sent = 0;
    Object? lastError;
    for (final friend in friends) {
      try {
        final cid = await SocialService.startConversation(friend.uid);
        await SocialService.sendMessage(cid, text);
        sent++;
      } catch (error) {
        lastError = error;
      }
    }
    if (sent > 0) unawaited(PostService.registerShare(_post.id));
    if (!mounted) return;
    Navigator.pop(context);
    if (sent == friends.length) {
      _toast(sent == 1
          ? 'تم إرسال $_noun إلى @${friends.first.username}'
          : 'تم إرسال $_noun إلى $sent أصدقاء');
    } else {
      _toast('تعذر إرسال $_noun إلى بعض الأصدقاء: $lastError');
    }
  }

  Future<void> _openExternal(String platform) async {
    final text = _shareText;
    final uri = switch (platform) {
      'whatsapp' => Uri.https('wa.me', '/', {'text': text}),
      'telegram' => Uri.https(
          't.me', '/share/url', {'url': _link, 'text': text.replaceAll(_link, '').trim()}),
      'facebook' =>
        Uri.https('www.facebook.com', '/sharer/sharer.php', {'u': _link}),
      'x' => Uri.https(
          'twitter.com', '/intent/tweet', {'url': _link, 'text': text.replaceAll(_link, '').trim()}),
      'sms' => Uri(scheme: 'sms', queryParameters: {'body': text}),
      _ => throw ArgumentError.value(platform, 'platform'),
    };
    Navigator.pop(context);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('تعذر فتح تطبيق المشاركة');
      unawaited(PostService.registerShare(_post.id));
    } catch (error) {
      _toast('تعذرت المشاركة: $error');
    }
  }

  Future<void> _copyLink() async {
    Navigator.pop(context);
    await Clipboard.setData(ClipboardData(text: _link));
    unawaited(PostService.registerShare(_post.id));
    _toast('تم نسخ رابط $_noun');
  }

  Future<void> _systemShare() async {
    Navigator.pop(context);
    try {
      final result = await Share.share(_shareText, subject: 'Haigram');
      if (result.status == ShareResultStatus.unavailable) {
        await Clipboard.setData(ClipboardData(text: _link));
        _toast('تم نسخ رابط $_noun');
      }
      if (result.status != ShareResultStatus.dismissed) {
        unawaited(PostService.registerShare(_post.id));
      }
    } catch (error) {
      _toast('تعذرت المشاركة: $error');
    }
  }

  bool get _mine => _post.uid == PostService.uidOrEmpty;

  /// يغلق الورقة ثم يفتح حوار تعديل النص (نستعمل سياق الـ root لأنه يبقى صالحاً).
  Future<void> _edit() async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final isText = _post.type == PostType.text;
    Navigator.pop(context);
    final controller = TextEditingController(text: _post.caption);
    final result = await showDialog<String>(
      context: rootContext,
      builder: (ctx) => AlertDialog(
        title: Text(isText ? 'تعديل المنشور' : 'تعديل الوصف'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          minLines: 1,
          maxLines: 6,
          decoration: InputDecoration(
              hintText: isText ? 'اكتب المنشور...' : 'اكتب وصفاً...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result == _post.caption) return;
    if (isText && !_post.hasVideo && result.isEmpty) {
      _toast('لا يمكن ترك المنشور فارغاً');
      return;
    }
    try {
      await PostService.updateCaption(_post, result);
      _toast('تم تعديل ${isText ? 'المنشور' : 'الوصف'}');
    } catch (error) {
      _toast('تعذر التعديل: $error');
    }
  }

  Future<void> _delete() async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    final ok = await showDialog<bool>(
      context: rootContext,
      builder: (ctx) => AlertDialog(
        title: Text('حذف $_noun؟'),
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
    if (ok != true) return;
    try {
      await PostService.deletePost(_post);
      _toast('تم حذف $_noun');
    } catch (error) {
      _toast('تعذر الحذف: $error');
    }
  }

  // ───────────────────────── واجهة ─────────────────────────

  Widget _item({
    required String label,
    required Widget icon,
    required VoidCallback? onTap,
    Color? background,
  }) {
    final colors = context.appColors;
    return SizedBox(
      width: 74,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background ?? colors.surfaceHigh,
                ),
                child: icon,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textDim, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: children,
        ),
      );

  Widget _friendItem(AppUser friend) {
    final colors = context.appColors;
    final selected = _selected.containsKey(friend.uid);
    return SizedBox(
      width: 78,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _sending
            ? null
            : () => setState(() {
                  if (selected) {
                    _selected.remove(friend.uid);
                  } else {
                    _selected[friend.uid] = friend;
                  }
                }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: IgnorePointer(
                      child: UserAvatar(
                        uid: friend.uid,
                        fallbackName: friend.username,
                        radius: 24,
                        showOnline: true,
                      ),
                    ),
                  ),
                  if (selected)
                    const PositionedDirectional(
                      end: -2,
                      bottom: -2,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: AppColors.accent,
                        child: Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                friend.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textDim, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendsRow() {
    final colors = context.appColors;
    return FutureBuilder<List<AppUser>>(
      future: _friends,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _hint('تعذر تحميل الأصدقاء');
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 96,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final friends = snapshot.data!;
        if (friends.isEmpty) {
          return _hint('ستظهر هنا الحسابات التي تتابعك وتتابعها لإرسال $_noun لها.',
              color: colors.textDim);
        }
        return _row(friends.map(_friendItem).toList());
      },
    );
  }

  Widget _hint(String text, {Color? color}) => SizedBox(
        height: 96,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color ?? context.appColors.textDim, fontSize: 13),
            ),
          ),
        ),
      );

  Widget _sendBar() {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _note,
              enabled: !_sending,
              maxLength: 200,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'أضف رسالة...',
                filled: true,
                fillColor: colors.surfaceHigh,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(88, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('إرسال${_selected.length > 1 ? ' (${_selected.length})' : ''}'),
          ),
        ],
      ),
    );
  }

  Widget _icon(IconData icon, [Color? color]) => Icon(
        icon,
        size: 24,
        color: color ?? context.appColors.text,
      );

  Widget _appsRow() {
    const white = Colors.white;
    return _row([
      _item(
        label: 'واتساب',
        background: const Color(0xFF25D366),
        icon: _icon(Icons.chat_rounded, white),
        onTap: () => _openExternal('whatsapp'),
      ),
      _item(
        label: 'تلغرام',
        background: const Color(0xFF229ED9),
        icon: _icon(Icons.send_rounded, white),
        onTap: () => _openExternal('telegram'),
      ),
      _item(
        label: 'فيسبوك',
        background: const Color(0xFF1877F2),
        icon: _icon(Icons.facebook, white),
        onTap: () => _openExternal('facebook'),
      ),
      _item(
        label: 'X',
        background: Colors.black,
        icon: _icon(Icons.alternate_email_rounded, white),
        onTap: () => _openExternal('x'),
      ),
      _item(
        label: 'رسالة SMS',
        background: const Color(0xFF34C759),
        icon: _icon(Icons.sms_rounded, white),
        onTap: () => _openExternal('sms'),
      ),
      _item(
        label: 'نسخ الرابط',
        icon: _icon(Icons.link_rounded),
        onTap: _copyLink,
      ),
      _item(
        label: 'المزيد',
        icon: _icon(Icons.more_horiz_rounded),
        onTap: _systemShare,
      ),
    ]);
  }

  Widget _actionsRow() {
    return StreamBuilder<bool>(
      stream: PostService.isSaved(_post.id),
      builder: (context, snapshot) {
        final saved = snapshot.data ?? false;
        return _row([
          _item(
            label: saved ? 'إزالة الحفظ' : 'حفظ',
            icon: _icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              saved ? context.appColors.reaction : null,
            ),
            onTap: () => _runAndClose(
              () => PostService.toggleSave(_post.id, saved),
              saved ? 'تمت الإزالة من المحفوظات' : 'تم الحفظ',
            ),
          ),
          if (_mine)
            _item(
              label: 'تعديل',
              icon: _icon(Icons.edit_outlined),
              onTap: _edit,
            ),
          if (_mine)
            _item(
              label: 'حذف',
              icon: _icon(Icons.delete_outline_rounded, AppColors.brandPurple),
              onTap: _delete,
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        'مشاركة إلى',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: colors.textDim),
                    ),
                  ],
                ),
              ),
              _friendsRow(),
              Divider(height: 1, color: colors.surfaceHigh),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sendBar(),
              ] else ...[
                const SizedBox(height: 4),
                _appsRow(),
                _actionsRow(),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
