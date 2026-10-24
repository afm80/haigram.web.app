import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../route_state.dart';
import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'story_backgrounds.dart';

String _errText(Object e) =>
    e is StateError ? e.message : tr('تعذّر الحفظ، حاول مرة أخرى');

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// صورة مصغّرة لقصة: تدرّج ونص للقصة النصية، وإلا الصورة نفسها.
class StoryThumb extends StatelessWidget {
  final Post story;
  final bool showText;
  const StoryThumb({super.key, required this.story, this.showText = true});

  @override
  Widget build(BuildContext context) {
    if (story.bg != null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: storyGradient(story.bg)),
        child: showText
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    story.caption,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              )
            : const SizedBox.expand(),
      );
    }
    return LayoutBuilder(
      builder: (_, c) => PostImage(
          post: story,
          fit: BoxFit.cover,
          height: c.maxHeight.isFinite ? c.maxHeight : null),
    );
  }
}

Future<String?> _askTitle(BuildContext context, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('اسم المميزة')),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 24,
        decoration: InputDecoration(hintText: tr('مميزة')),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء'))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(tr('حفظ'))),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إلغاء'))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(tr('حذف'))),
      ],
    ),
  );
  return ok == true;
}

/// مميزة جديدة: اختيار قصص من الأرشيف ثم تسميتها وحفظها.
Future<void> startNewHighlight(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<Post>>(
      MaterialPageRoute(builder: (_) => const StoryArchiveScreen(pick: true)));
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final title = await _askTitle(context);
  if (title == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await PostService.saveHighlight(title: title, stories: picked);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_errText(e))));
  }
}

/// أرشيف قصصي (وضع العرض)، أو اختيار قصص لإضافتها إلى مميزة (وضع [pick]).
class StoryArchiveScreen extends StatefulWidget {
  final bool pick;
  final Set<String> excludeIds; // قصص موجودة في المميزة أصلاً
  final int maxPick;
  const StoryArchiveScreen(
      {super.key,
      this.pick = false,
      this.excludeIds = const {},
      this.maxPick = PostService.maxHighlightItems});

  @override
  State<StoryArchiveScreen> createState() => _StoryArchiveScreenState();
}

class _StoryArchiveScreenState extends State<StoryArchiveScreen> {
  final List<Post> _items = [];
  final Set<String> _sel = {};
  final ScrollController _sc = ScrollController();
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = true;
  bool _more = true;
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.hasClients &&
          _sc.position.pixels > _sc.position.maxScrollExtent - 400) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    _busy = true;
    try {
      final page = await PostService.archivePage(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.posts);
        _cursor = page.cursor ?? _cursor;
        _more = page.hasMore;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  void _toggle(Post p) {
    if (widget.excludeIds.contains(p.id)) return;
    if (p.closeFriends) {
      _toast(tr('قصص الأصدقاء المقربين لا تُضاف إلى المميزة'));
      return;
    }
    if (_sel.contains(p.id)) {
      setState(() => _sel.remove(p.id));
    } else if (_sel.length >= widget.maxPick) {
      _toast(tr('بلغت الحد الأقصى للقصص في المميزة'));
    } else {
      setState(() => _sel.add(p.id));
    }
  }

  void _done() {
    final chosen = [
      for (final p in _items)
        if (_sel.contains(p.id)) p
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    Navigator.of(context).pop(chosen);
  }

  Future<void> _delete(Post p) async {
    if (!await _confirm(context, tr('حذف القصة من الأرشيف؟'))) return;
    await PostService.deleteFromArchive(p.id);
    if (mounted) setState(() => _items.removeWhere((e) => e.id == p.id));
  }

  void _open(int index) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => StoryListViewer(
        stories: List<Post>.of(_items),
        initial: index,
        removeLabel: tr('حذف من الأرشيف'),
        removeConfirm: tr('حذف القصة من الأرشيف؟'),
        onRemove: (p, i) async {
          await PostService.deleteFromArchive(p.id);
          if (mounted) setState(() => _items.removeWhere((e) => e.id == p.id));
          return true;
        },
      ),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  Widget _tile(int i) {
    final p = _items[i];
    final excluded = widget.excludeIds.contains(p.id);
    final selected = _sel.contains(p.id);
    return GestureDetector(
      onTap: () => widget.pick ? _toggle(p) : _open(i),
      onLongPress: widget.pick ? null : () => _delete(p),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StoryThumb(story: p),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000)],
                stops: [0.6, 1],
              ),
            ),
          ),
          PositionedDirectional(
            start: 6,
            bottom: 5,
            child: Text(_fmtDate(p.createdAt),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          if (p.closeFriends)
            PositionedDirectional(
              top: 5,
              end: 5,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xFF22C55E)),
                child: const Icon(Icons.star_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          if (widget.pick && (selected || excluded || p.closeFriends))
            ColoredBox(
              color: selected ? const Color(0x55000000) : const Color(0x99000000),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : (excluded
                            ? Icons.done_rounded
                            : Icons.block_rounded),
                    color: selected ? const Color(0xFF3B82F6) : Colors.white70,
                    size: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_error ? Icons.wifi_off_rounded : Icons.archive_outlined,
                  size: 48, color: c.textDim),
              const SizedBox(height: 12),
              Text(
                _error
                    ? tr('تعذّر تحميل الأرشيف')
                    : tr('لا توجد قصص في الأرشيف بعد. القصص التي تنشرها تُحفظ هنا تلقائياً بعد انتهائها.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textDim, height: 1.5),
              ),
              if (_error)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _more = true;
                    });
                    _load();
                  },
                  child: Text(tr('إعادة المحاولة')),
                ),
            ],
          ),
        ),
      );
    } else {
      body = GridView.builder(
        controller: _sc,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 9 / 16,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _tile(i),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? tr('اختر القصص') : tr('أرشيف القصص')),
        actions: [
          if (!widget.pick)
            IconButton(
              tooltip: tr('مميزة جديدة'),
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => startNewHighlight(context),
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: widget.pick
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: FilledButton(
                  onPressed: _sel.isEmpty ? null : _done,
                  child: Text('${tr('التالي')} (${_sel.length})'),
                ),
              ),
            )
          : null,
    );
  }
}

/// صف القصص المميزة في الملف الشخصي. لصاحب الحساب: «جديد» و«الأرشيف» أولاً،
/// وضغطة مطوّلة على مميزة لإعادة تسميتها أو إضافة قصص أو حذفها.
class StoryHighlightsRow extends StatefulWidget {
  final String uid;
  final bool isMe;
  const StoryHighlightsRow({super.key, required this.uid, required this.isMe});

  @override
  State<StoryHighlightsRow> createState() => _StoryHighlightsRowState();
}

class _StoryHighlightsRowState extends State<StoryHighlightsRow> {
  late Stream<List<StoryHighlight>> _stream =
      PostService.highlightsOf(widget.uid);

  @override
  void didUpdateWidget(covariant StoryHighlightsRow old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _stream = PostService.highlightsOf(widget.uid);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  Widget _cell({required Widget circle, required String label}) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: SizedBox(
          width: 66,
          child: Column(
            children: [
              circle,
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _action(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    final c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: _cell(
        label: label,
        circle: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.textDim, width: 1.2)),
          child: Icon(icon, color: c.text, size: 26),
        ),
      ),
    );
  }

  Widget _circle(StoryHighlight h) {
    final c = context.appColors;
    final cover = h.coverStory;
    return GestureDetector(
      onTap: () => _open(h),
      onLongPress: widget.isMe ? () => _manage(h) : null,
      child: _cell(
        label: h.title,
        circle: Container(
          width: 62,
          height: 62,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.textDim, width: 1.2)),
          child: ClipOval(
              child: cover == null
                  ? const SizedBox.expand()
                  : StoryThumb(story: cover, showText: false)),
        ),
      ),
    );
  }

  void _open(StoryHighlight h) {
    // نسخة محلية تتبع ما يحذفه/يغيّره المالك أثناء المشاهدة.
    final current = List<Post>.of(h.stories);
    var coverId = h.coverStory?.id;
    int coverIdx() => math.max(0, current.indexWhere((e) => e.id == coverId));

    Future<bool> remove(Post p, int idx) async {
      current.removeWhere((e) => e.id == p.id);
      try {
        if (current.isEmpty) {
          await PostService.deleteHighlight(h.id);
        } else {
          await PostService.saveHighlight(
              id: h.id, title: h.title, stories: current, cover: coverIdx());
        }
        return true;
      } catch (e) {
        current.insert(math.min(idx, current.length), p);
        if (mounted) _toast(_errText(e));
        return false;
      }
    }

    Future<void> setCover(int idx) async {
      if (idx < 0 || idx >= current.length) return;
      try {
        await PostService.saveHighlight(
            id: h.id, title: h.title, stories: current, cover: idx);
        coverId = current[idx].id;
        if (mounted) _toast(tr('تم تعيين الغلاف'));
      } catch (e) {
        if (mounted) _toast(_errText(e));
      }
    }

    rootNavigatorOf(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, __, ___) => StoryListViewer(
          stories: h.stories,
          title: h.title,
          removeLabel: tr('إزالة من المميزة'),
          removeConfirm: tr('إزالة القصة من المميزة؟'),
          onRemove: widget.isMe ? remove : null,
          onSetCover: widget.isMe ? setCover : null,
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  Future<void> _manage(StoryHighlight h) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('إعادة تسمية')),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(tr('إضافة قصص من الأرشيف')),
              onTap: () => Navigator.pop(ctx, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('حذف المميزة')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'rename') {
        final t = await _askTitle(context, initial: h.title);
        if (t == null) return;
        await PostService.saveHighlight(
            id: h.id, title: t, stories: h.stories, cover: h.cover);
      } else if (action == 'add') {
        final room = PostService.maxHighlightItems - h.stories.length;
        if (room <= 0) {
          _toast(tr('بلغت الحد الأقصى للقصص في المميزة'));
          return;
        }
        final picked = await Navigator.of(context).push<List<Post>>(
            MaterialPageRoute(
                builder: (_) => StoryArchiveScreen(
                    pick: true,
                    excludeIds: {for (final s in h.stories) s.id},
                    maxPick: room)));
        if (picked == null || picked.isEmpty) return;
        await PostService.saveHighlight(
            id: h.id,
            title: h.title,
            stories: [...h.stories, ...picked],
            cover: h.cover);
      } else if (action == 'delete') {
        if (!await _confirm(context, tr('حذف هذه المميزة؟'))) return;
        await PostService.deleteHighlight(h.id);
      }
    } catch (e) {
      if (mounted) _toast(_errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoryHighlight>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <StoryHighlight>[];
        if (!widget.isMe && list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 94,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 8),
            children: [
              if (widget.isMe)
                _action(
                  icon: Icons.add_rounded,
                  label: tr('جديد'),
                  onTap: () => startNewHighlight(context),
                ),
              if (widget.isMe)
                _action(
                  icon: Icons.archive_outlined,
                  label: tr('الأرشيف'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const StoryArchiveScreen())),
                ),
              for (final h in list) _circle(h),
            ],
          ),
        );
      },
    );
  }
}

/// عارض بسيط لقائمة قصص (الأرشيف أو مميزة): تقدّم تلقائي كل 5 ثوانٍ،
/// لمسة للتنقل، ضغط مطوّل للإيقاف، وسحب للأسفل للإغلاق. بلا ردود أو تفاعلات
/// لأن القصة الأصلية انتهت.
class StoryListViewer extends StatefulWidget {
  final List<Post> stories;
  final int initial;
  final String? title;
  final String removeLabel;
  final String removeConfirm;
  final Future<bool> Function(Post story, int index)? onRemove;
  final Future<void> Function(int index)? onSetCover;

  const StoryListViewer({
    super.key,
    required this.stories,
    this.initial = 0,
    this.title,
    this.removeLabel = '',
    this.removeConfirm = '',
    this.onRemove,
    this.onSetCover,
  });

  @override
  State<StoryListViewer> createState() => _StoryListViewerState();
}

class _StoryListViewerState extends State<StoryListViewer>
    with SingleTickerProviderStateMixin {
  late final List<Post> _list = List<Post>.of(widget.stories);
  late int _i = _list.isEmpty
      ? 0
      : widget.initial.clamp(0, _list.length - 1).toInt();
  late final AnimationController _t;
  final Set<String> _pause = {};
  String? _readyId;
  bool _hideUi = false;
  double _dragDy = 0;

  Post get _story => _list[_i];

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfText());
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _startIfText() {
    if (mounted && _list.isNotEmpty && _story.bg != null) _onLoaded(_story.id);
  }

  /// يبدأ العدّاد مرة واحدة لكل قصة بعد ظهورها (الصورة قد تُبلغ أكثر من مرة).
  void _onLoaded(String id) {
    if (!mounted || _list.isEmpty || id != _story.id || _readyId == id) return;
    _readyId = id;
    if (_pause.isEmpty) {
      _t.forward(from: 0);
    } else {
      _t.value = 0;
    }
  }

  void _setPause(String reason, bool on) {
    if (!mounted) return;
    on ? _pause.add(reason) : _pause.remove(reason);
    if (_pause.isNotEmpty) {
      _t.stop();
    } else if (_list.isNotEmpty && _readyId == _story.id) {
      _t.forward();
    }
    setState(() {});
  }

  void _go(int n) {
    _t.stop();
    _t.value = 0;
    _readyId = null;
    setState(() => _i = n);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfText());
  }

  void _next() {
    if (!mounted) return;
    if (_i < _list.length - 1) {
      _go(_i + 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_i > 0) {
      _go(_i - 1);
    } else {
      _t.forward(from: 0);
    }
  }

  Future<void> _menu() async {
    final story = _story;
    final index = _i;
    _setPause('menu', true);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (widget.onSetCover != null)
              ListTile(
                leading:
                    const Icon(Icons.photo_outlined, color: Colors.white),
                title: Text(tr('تعيين كغلاف'),
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'cover'),
              ),
            if (widget.onRemove != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.white),
                title: Text(widget.removeLabel,
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'cover') {
      await widget.onSetCover!(index);
    } else if (action == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(widget.removeConfirm),
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
      if (ok == true && mounted && await widget.onRemove!(story, index)) {
        if (!mounted) return;
        _list.removeWhere((e) => e.id == story.id);
        if (_list.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        _pause.remove('menu');
        _go(math.min(index, _list.length - 1));
        return;
      }
    }
    _setPause('menu', false);
  }

  Widget _media(Post story) {
    if (story.bg != null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: storyGradient(story.bg)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 90),
            child: Text(
              story.caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.4,
                shadows: [Shadow(blurRadius: 6, color: Color(0x55000000))],
              ),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, c) => ColoredBox(
        color: const Color(0xFF111111),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child:
                  PostImage(post: story, fit: BoxFit.cover, height: c.maxHeight),
            ),
            const ColoredBox(color: Color(0x66000000)),
            Center(
              child: PostImage(
                  post: story,
                  fit: BoxFit.contain,
                  height: c.maxHeight,
                  onLoaded: () => _onLoaded(story.id)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: AnimatedBuilder(
          animation: _t,
          builder: (_, __) => Row(
            children: [
              for (var i = 0; i < _list.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: i < _i ? 1 : (i == _i ? _t.value : 0),
                        minHeight: 2.5,
                        backgroundColor: Colors.white30,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _header(Post story) {
    final hasMenu = widget.onRemove != null || widget.onSetCover != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          UserAvatar(
              uid: story.uid, fallbackName: story.username, radius: 17),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title ?? story.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text(_fmtDate(story.createdAt),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const Spacer(),
          if (hasMenu)
            IconButton(
                onPressed: _menu,
                icon: const Icon(Icons.more_horiz, color: Colors.white)),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final story = _story;
    final scale = (1 - (_dragDy / 1200)).clamp(0.85, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final inPrevZone =
              rtl ? d.localPosition.dx > w * 2 / 3 : d.localPosition.dx < w / 3;
          inPrevZone ? _prev() : _next();
        },
        onLongPressStart: (_) {
          _hideUi = true;
          _setPause('hold', true);
        },
        onLongPressEnd: (_) {
          _hideUi = false;
          _setPause('hold', false);
        },
        onVerticalDragStart: (_) => _setPause('drag', true),
        onVerticalDragUpdate: (d) => setState(
            () => _dragDy = (_dragDy + d.delta.dy).clamp(0.0, 600.0).toDouble()),
        onVerticalDragEnd: (d) {
          if (_dragDy > 120 || (d.primaryVelocity ?? 0) > 700) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragDy = 0);
            _setPause('drag', false);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: Transform.scale(
            scale: scale,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      KeyedSubtree(
                          key: ValueKey(story.id), child: _media(story)),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x99000000),
                                Colors.transparent,
                                Colors.transparent,
                                Color(0x88000000),
                              ],
                              stops: [0, 0.22, 0.75, 1],
                            ),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hideUi ? 0 : 1,
                        child: Column(
                          children: [
                            _progress(),
                            _header(story),
                            const Spacer(),
                            if (story.bg == null && story.caption.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                child: Text(
                                  story.caption,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 6,
                                            color: Color(0x88000000))
                                      ]),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
