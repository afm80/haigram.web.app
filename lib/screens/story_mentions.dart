import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/post_service.dart';
import '../services/social_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// يرسل لكل مستخدم مذكور رسالة خاصة (مثل إنستغرام). لا يوقف النشر إن فشل أحدها.
Future<void> notifyStoryMentions(List<StoryMention> mentions) async {
  for (final m in mentions) {
    try {
      final me = PostService.username;
      final id = await SocialService.startConversation(m.uid);
      await SocialService.sendMessage(id, trf('ذكرك @{0} في قصته', [me]));
    } catch (_) {}
  }
}

/// نافذة البحث عن مستخدم لذكره. تعيد null عند الإغلاق دون اختيار.
Future<StoryMention?> showMentionPicker(BuildContext context,
    {Set<String> exclude = const {}}) {
  return showModalBottomSheet<StoryMention>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MentionPicker(exclude: exclude),
  );
}

class _MentionPicker extends StatefulWidget {
  final Set<String> exclude;
  const _MentionPicker({required this.exclude});

  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<AppUser> _results = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _seq++;
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    List<AppUser> found;
    try {
      found = await UserService.search(q);
    } catch (_) {
      found = const [];
    }
    if (!mounted || seq != _seq) return;
    final me = PostService.uidOrEmpty;
    setState(() {
      _results = [
        for (final u in found)
          if (u.uid != me && !widget.exclude.contains(u.uid)) u,
      ];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasText = _q.text.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: tr('ابحث عن مستخدم'),
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        (hasText && !_loading) ? tr('لا توجد نتائج') : '',
                        style: TextStyle(color: colors.textDim),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final u = _results[i];
                        return ListTile(
                          leading: UserAvatar(
                              uid: u.uid,
                              fallbackName: u.username,
                              radius: 20,
                              profile: u),
                          title: Text(u.username),
                          subtitle: u.name.isEmpty ? null : Text(u.name),
                          onTap: () => Navigator.of(context).pop(
                              StoryMention(uid: u.uid, username: u.username)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// زر «ذكر» مع شرائح المذكورين (حتى 3) في شاشة إنشاء القصة.
/// القائمة [mentions] تُعدَّل مباشرة، ويُستدعى [onChanged] بعد كل تغيير.
class MentionEditor extends StatelessWidget {
  static const maxMentions = 3;
  final List<StoryMention> mentions;
  final bool enabled;
  final VoidCallback onChanged;
  final Color? color;
  const MentionEditor(
      {super.key,
      required this.mentions,
      required this.onChanged,
      this.enabled = true,
      this.color});

  Future<void> _add(BuildContext context) async {
    final m = await showMentionPicker(context,
        exclude: {for (final x in mentions) x.uid});
    if (m == null) return;
    mentions.add(m);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (mentions.length < maxMentions)
          TextButton.icon(
            onPressed: enabled ? () => _add(context) : null,
            icon: Icon(Icons.alternate_email_rounded, color: color),
            label: Text(tr('ذكر'), style: TextStyle(color: color)),
          ),
        for (final m in mentions)
          InputChip(
            label: Text('@${m.username}'),
            onDeleted: enabled
                ? () {
                    mentions.remove(m);
                    onChanged();
                  }
                : null,
          ),
      ],
    );
  }
}

/// شرائح المذكورين فوق القصة: الضغط على أي منها يفتح ملفه.
class StoryMentionsRow extends StatelessWidget {
  final List<StoryMention> mentions;
  final void Function(String uid) onOpen;
  const StoryMentionsRow(
      {super.key, required this.mentions, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final m in mentions)
          Material(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onOpen(m.uid),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text('@${m.username}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ),
      ],
    );
  }
}
