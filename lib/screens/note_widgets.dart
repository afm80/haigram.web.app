import 'package:flutter/material.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/note_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart' show timeAgo;

/// فقاعة الملاحظة فوق الصورة (مثل «Notes» في إنستغرام): نص قصير داخل سحابة
/// صغيرة لها ذيل من دائرتين باتجاه الصورة.
class NoteBubble extends StatelessWidget {
  final String text;

  /// فقاعة فارغة تدعو صاحب الحساب لكتابة ملاحظة («ملاحظة...»).
  final bool placeholder;
  final VoidCallback? onTap;

  const NoteBubble({
    super.key,
    required this.text,
    this.placeholder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dot = BoxDecoration(color: colors.surfaceHigh, shape: BoxShape.circle);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 36, maxWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textDirection: SocialService.inferTextDirection(text),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                color: placeholder ? colors.textDim : colors.text,
                fontWeight: placeholder ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
          // ذيل الفقاعة: دائرتان تتصاغران نحو الصورة.
          SizedBox(
            width: 18,
            height: 11,
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 3,
                  top: 0,
                  child: Container(width: 8, height: 8, decoration: dot),
                ),
                PositionedDirectional(
                  start: 8,
                  top: 7,
                  child: Container(width: 4, height: 4, decoration: dot),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عنصر في صف صندوق البريد: فقاعة الملاحظة (إن وُجدت) ثم الصورة ثم الاسم.
/// الضغط على الفقاعة يفتح الملاحظة، والضغط على الصورة يبقى كما كان (قصة/محادثة).
class NoteRailItem extends StatelessWidget {
  final String uid;
  final AppUser? profile;
  final UserNote? note;
  final bool isMine;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback onAvatarTap;
  final VoidCallback onNoteTap;

  const NoteRailItem({
    super.key,
    required this.uid,
    required this.profile,
    required this.note,
    required this.isMine,
    required this.hasStory,
    required this.storySeen,
    required this.onAvatarTap,
    required this.onNoteTap,
  });

  /// ارتفاع منطقة الفقاعة فوق الصورة.
  static const bubbleZone = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final showBubble = note != null || isMine;
    final label = isMine ? tr('ملاحظتك') : (profile?.username ?? '');
    return SizedBox(
      width: 84,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: bubbleZone,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: showBubble
                  ? NoteBubble(
                      text: note?.text ?? tr('ملاحظة...'),
                      placeholder: note == null,
                      onTap: onNoteTap,
                    )
                  : null,
            ),
          ),
          GestureDetector(
            onTap: isMine && note == null ? onNoteTap : onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  uid: uid,
                  profile: profile,
                  fallbackName: profile?.username ?? '',
                  radius: 32,
                  showOnline: !isMine,
                  hasStory: hasStory,
                  storySeen: storySeen,
                ),
                if (isMine && note == null)
                  PositionedDirectional(
                    end: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.brandPurple,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.bg, width: 2),
                      ),
                      child: const Icon(Icons.add_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.text),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// كتابة ملاحظة جديدة
// ---------------------------------------------------------------------------

/// يفتح نافذة كتابة ملاحظة. يعيد true إذا نُشرت.
Future<bool> showNoteComposeSheet(
  BuildContext context, {
  UserNote? existing,
}) async {
  final shared = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NoteComposeSheet(replacing: existing != null),
  );
  return shared == true;
}

class _NoteComposeSheet extends StatefulWidget {
  final bool replacing;
  const _NoteComposeSheet({required this.replacing});

  @override
  State<_NoteComposeSheet> createState() => _NoteComposeSheetState();
}

class _NoteComposeSheetState extends State<_NoteComposeSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canShare => _controller.text.trim().isNotEmpty && !_sending;

  Future<void> _share() async {
    if (!_canShare) return;
    setState(() => _sending = true);
    try {
      await NoteService.post(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: tr('تعذرت مشاركة الملاحظة'))),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final me = UserService.me;
    final length = _controller.text.characters.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr('ملاحظة جديدة'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _canShare ? _share : null,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            tr('مشاركة'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // فقاعة الكتابة فوق صورتي.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    enabled: !_sending,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: UserNote.maxLength,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _share(),
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: tr('شارك ما يدور في بالك...'),
                      hintStyle: TextStyle(color: colors.textDim),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: SizedBox(
                  width: 18,
                  height: 11,
                  child: Stack(
                    children: [
                      PositionedDirectional(
                        start: 5,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: colors.surfaceHigh,
                              shape: BoxShape.circle),
                        ),
                      ),
                      PositionedDirectional(
                        start: 9,
                        top: 7,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                              color: colors.surfaceHigh,
                              shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              UserAvatar(
                uid: SocialService.currentUid,
                profile: me,
                fallbackName: me?.username ?? '',
                radius: 38,
              ),
              const SizedBox(height: 6),
              Text(
                '$length/${UserNote.maxLength}',
                style: TextStyle(color: colors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.bg2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 22, color: colors.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('المتابعون الذين تتابعهم'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr('تظهر ملاحظتك لمن تتابعه ويتابعك، وتختفي بعد 24 ساعة.'),
                            style: TextStyle(
                                color: colors.textDim, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.replacing)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    tr('ستحل هذه الملاحظة محل ملاحظتك الحالية.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textDim, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// خيارات ملاحظتي (ملاحظة جديدة / حذف)
// ---------------------------------------------------------------------------

Future<void> showMyNoteOptions(BuildContext context, UserNote note) async {
  final colors = context.appColors;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              children: [
                NoteBubble(text: note.text),
                const SizedBox(height: 4),
                Text(
                  trf('شاركتها {0}', [timeAgo(note.createdAt)]),
                  style: TextStyle(color: colors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(tr('ملاحظة جديدة')),
            onTap: () => Navigator.of(sheetContext).pop('new'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: AppColors.likeRed),
            title: Text(
              tr('حذف الملاحظة'),
              style: const TextStyle(color: AppColors.likeRed),
            ),
            onTap: () => Navigator.of(sheetContext).pop('delete'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'new') {
    await showNoteComposeSheet(context, existing: note);
    return;
  }
  try {
    await NoteService.delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم حذف الملاحظة'))),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: tr('تعذر الحذف'))),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// الردّ على ملاحظة صديق
// ---------------------------------------------------------------------------

Future<void> showNoteReplySheet(
  BuildContext context, {
  required UserNote note,
  required AppUser? owner,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NoteReplySheet(note: note, owner: owner),
  );
}

class _NoteReplySheet extends StatefulWidget {
  final UserNote note;
  final AppUser? owner;
  const _NoteReplySheet({required this.note, required this.owner});

  @override
  State<_NoteReplySheet> createState() => _NoteReplySheetState();
}

class _NoteReplySheetState extends State<_NoteReplySheet> {
  static const _quick = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await NoteService.reply(widget.note, trimmed);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('تم إرسال ردّك'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: tr('تعذر إرسال الردّ'))),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final owner = widget.owner;
    final name = owner?.username ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.surfaceHigh,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: NoteBubble(text: widget.note.text),
              ),
              UserAvatar(
                uid: widget.note.uid,
                profile: owner,
                fallbackName: name,
                radius: 36,
              ),
              const SizedBox(height: 8),
              Text(
                owner?.displayName ?? tr('مستخدم'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                trf('{0} • تنتهي بعد {1}', [
                  timeAgo(widget.note.createdAt),
                  _remainingLabel(widget.note.remaining),
                ]),
                style: TextStyle(color: colors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _quick)
                    InkResponse(
                      onTap: _sending ? null : () => _send(emoji),
                      radius: 24,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceHigh,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_sending,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _send,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: name.isEmpty
                              ? tr('ردّ على الملاحظة...')
                              : trf('ردّ على ملاحظة {0}...', [name]),
                          hintStyle: TextStyle(color: colors.textDim),
                        ),
                      ),
                    ),
                    _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            onPressed: _controller.text.trim().isEmpty
                                ? null
                                : () => _send(_controller.text),
                            icon: Icon(
                              Icons.send_rounded,
                              color: _controller.text.trim().isEmpty
                                  ? colors.textDim
                                  : AppColors.brandPurple,
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

  String _remainingLabel(Duration d) {
    if (d.inHours >= 1) return trf('{0} س', [d.inHours]);
    final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
    return trf('{0} د', [minutes]);
  }
}
