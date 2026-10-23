import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// أخضر الأصدقاء المقربين (حلقة القصة وشارتها).
const kCloseFriendsGreen = Color(0xFF22C55E);

const closeFriendsGradient = LinearGradient(
  colors: [Color(0xFF86EFAC), Color(0xFF22C55E), Color(0xFF15803D)],
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
);

/// اختيار جمهور القصة: الجميع أو الأصدقاء المقربون.
/// عند اختيار «المقربون» وقائمتك فارغة تُفتح شاشة اختيار الأصدقاء أولاً.
class StoryAudienceSelector extends StatelessWidget {
  final bool close;
  final bool enabled;
  final Color? color;
  final ValueChanged<bool> onChanged;
  const StoryAudienceSelector(
      {super.key,
      required this.close,
      required this.onChanged,
      this.enabled = true,
      this.color});

  Future<void> _pickClose(BuildContext context) async {
    List<String> ids;
    try {
      ids = await PostService.closeFriendIds();
    } catch (_) {
      ids = const [];
    }
    if (ids.isEmpty) {
      if (!context.mounted) return;
      final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const CloseFriendsScreen()));
      if (saved != true) return;
      try {
        ids = await PostService.closeFriendIds();
      } catch (_) {
        ids = const [];
      }
      if (ids.isEmpty) return;
    }
    onChanged(true);
  }

  Widget _pill(BuildContext context,
      {required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required Color activeColor}) {
    final fg = color ?? context.appColors.text;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? activeColor : Colors.transparent,
          border: Border.all(
              color: selected ? activeColor : fg.withAlpha(115), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : fg)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.appColors.text;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _pill(context,
            selected: !close,
            icon: Icons.public_rounded,
            label: tr('الجميع'),
            activeColor: AppColors.brandPurple,
            onTap: () => onChanged(false)),
        _pill(context,
            selected: close,
            icon: Icons.star_rounded,
            label: tr('الأصدقاء المقربون'),
            activeColor: kCloseFriendsGreen,
            onTap: () => _pickClose(context)),
        if (close)
          TextButton(
            onPressed: enabled
                ? () => Navigator.of(context).push<bool>(MaterialPageRoute(
                    builder: (_) => const CloseFriendsScreen()))
                : null,
            child: Text(tr('تعديل القائمة'), style: TextStyle(color: fg)),
          ),
      ],
    );
  }
}

/// شاشة إدارة قائمة الأصدقاء المقربين (حتى 100). تعيد true عند الحفظ.
class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  final Set<String> _sel = {};
  List<String> _candidates = const []; // متابعوني ومن أتابعهم
  List<AppUser> _results = const []; // نتائج البحث
  bool _loading = true;
  bool _searching = false;
  bool _saving = false;
  bool _loadFailed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = PostService.uidOrEmpty;
    try {
      final r = await Future.wait([
        PostService.closeFriendIds(),
        PostService.followerIdsOnce(me),
        PostService.followingIdsOnce(me),
      ]);
      final saved = r[0];
      final others = <String>{...r[1], ...r[2]}..remove(me);
      // المختارون أولاً ثم الباقي.
      final ordered = [
        ...saved.where(others.contains),
        ...others.where((u) => !saved.contains(u)),
      ];
      if (!mounted) return;
      setState(() {
        _sel.addAll(saved);
        _candidates = [...saved.where((u) => !others.contains(u)), ...ordered];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _seq++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _searching = true);
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
          if (u.uid != me) u,
      ];
      _searching = false;
    });
  }

  void _toggle(String uid) {
    if (_sel.contains(uid)) {
      setState(() => _sel.remove(uid));
      return;
    }
    if (_sel.length >= PostService.maxCloseFriends) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(trf('الحد الأقصى {0} صديقاً مقرباً',
              [PostService.maxCloseFriends]))));
      return;
    }
    setState(() => _sel.add(uid));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.saveCloseFriends(_sel);
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e, fallback: tr('تعذّر الحفظ')))));
    }
  }

  Widget _row(String uid, {AppUser? user}) {
    Widget tile(AppUser u) => ListTile(
          leading: UserAvatar(
              uid: u.uid, fallbackName: u.username, radius: 20, profile: u),
          title: Text(u.username),
          subtitle: u.name.isEmpty ? null : Text(u.name),
          trailing: Icon(
            _sel.contains(uid)
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: _sel.contains(uid)
                ? kCloseFriendsGreen
                : context.appColors.textDim,
          ),
          onTap: () => _toggle(uid),
        );
    if (user != null) return tile(user);
    return FutureBuilder<AppUser?>(
      future: UserService.profileOf(uid),
      builder: (_, snap) {
        final u = snap.data;
        if (u == null) return const SizedBox.shrink();
        return tile(u);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final searching = _q.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('الأصدقاء المقربون')),
        actions: [
          TextButton(
            onPressed: (_saving || _loading) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('حفظ'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: tr('ابحث عن مستخدم'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: kCloseFriendsGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trf('{0} من {1} — قصصك المقربة يراها هؤلاء فقط',
                        [_sel.length, PostService.maxCloseFriends]),
                    style: TextStyle(color: colors.textDim, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          if (_loading || _searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: searching
                ? (_results.isEmpty
                    ? Center(
                        child: Text(
                            _searching ? '' : tr('لا توجد نتائج'),
                            style: TextStyle(color: colors.textDim)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) =>
                            _row(_results[i].uid, user: _results[i]),
                      ))
                : (_candidates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _loading
                                ? ''
                                : (_loadFailed
                                    ? tr('تعذّر تحميل القائمة')
                                    : tr('ابحث عن مستخدم لإضافته إلى أصدقائك المقربين')),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textDim),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _candidates.length,
                        itemBuilder: (_, i) => _row(_candidates[i]),
                      )),
          ),
        ],
      ),
    );
  }
}
