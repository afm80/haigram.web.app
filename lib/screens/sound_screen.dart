// صفحة قرص الصوت (تُفتح من قرص الصوت في الشورتز أو من سطر اسم الصوت):
// تشغيل الصوت، استخدام الصوت في فيديو جديد، نشره في قصة، حفظه، وقائمة
// الفيديوهات التي تستخدم الصوت نفسه. وفيها أيضاً «الأصوات المحفوظة».
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import '../net_error.dart';
import '../route_state.dart';
import '../services/post_service.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'create_flow.dart' show CreateKind, startCreate;
import 'post_widgets.dart' show showShortDialog;
import 'video_cover.dart';
import 'video_upload_screen.dart';

String _compact(int n) {
  String t(double v) =>
      v.toStringAsFixed(v < 10 ? 1 : 0).replaceFirst(RegExp(r'\.0$'), '');
  if (n < 1000) return '$n';
  if (n < 1000000) return '${t(n / 1000)}K';
  return '${t(n / 1000000)}M';
}

/// عنوان الصوت للعرض (الصوت الأصلي يُترجم، وغيره كما هو).
String soundTitle(PostSound s) => tr(s.title);

/// يفتح صفحة الصوت. [root] لفتحها فوق عارض الشورتز (نافذة بملء الشاشة).
void openSound(BuildContext context, PostSound sound, {bool root = false}) {
  final route = appRoute<void>(
      'sound', sound.toMap(), (_) => SoundScreen(sound: sound));
  Navigator.of(context, rootNavigator: root).push(route);
}

class SoundScreen extends StatefulWidget {
  final PostSound sound;
  const SoundScreen({super.key, required this.sound});

  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _player = AudioPlayer();
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final Stream<bool> _saved = SoundService.isSaved(widget.sound.id);

  Post? _original;
  bool _headLoaded = false;
  Object? _error;
  int _uses = 0;
  final _posts = <Post>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _player.onPlayerComplete.listen((_) => _setPlaying(false));
    _loadHead();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _spin.dispose();
    _player.dispose();
    super.dispose();
  }

  void _setPlaying(bool v) {
    if (!mounted) return;
    setState(() => _playing = v);
    if (v) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  Future<void> _loadHead() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object?>([
        SoundService.original(widget.sound.id),
        SoundService.usesCount(widget.sound.id),
        SoundService.videosPage(widget.sound.id),
      ]);
      if (!mounted) return;
      final page = results[2] as PostPage;
      setState(() {
        _original = results[0] as Post?;
        _uses = results[1] as int;
        _posts
          ..clear()
          ..addAll(page.posts);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _headLoaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !_headLoaded) return;
    _loadingMore = true;
    try {
      final page =
          await SoundService.videosPage(widget.sound.id, after: _cursor);
      if (!mounted) return;
      setState(() {
        final seen = _posts.map((p) => p.id).toSet();
        _posts.addAll(page.posts.where((p) => !seen.contains(p.id)));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // نتوقف عن التحميل التلقائي؛ يعيد المستخدم المحاولة بالتمرير من جديد.
    } finally {
      _loadingMore = false;
    }
  }

  /// كل الفيديوهات: الأصلي أولاً ثم من استخدموا الصوت.
  List<Post> get _all => [if (_original != null) _original!, ..._posts];

  Future<void> _togglePlay() async {
    final url = _original?.video?.url;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('الصوت الأصلي لم يعد متاحاً'))));
      return;
    }
    try {
      if (_playing) {
        await _player.pause();
        _setPlaying(false);
      } else {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.play(UrlSource(url));
        _setPlaying(true);
      }
    } catch (e) {
      _setPlaying(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, fallback: tr('تعذر تشغيل الصوت')))));
      }
    }
  }

  Future<void> _toggleSave(bool saved) async {
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SoundService.toggleSave(widget.sound, saved);
      messenger.showSnackBar(SnackBar(
          content: Text(saved ? tr('أُزيل الصوت من المحفوظات') : tr('تم حفظ الصوت'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e, fallback: tr('تعذر تنفيذ العملية')))));
    }
  }

  Future<void> _useSound() async {
    if (needsLogin(context)) return;
    await _player.pause();
    _setPlaying(false);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoUploadScreen(sound: widget.sound)));
  }

  Future<void> _postToStory() async {
    if (needsLogin(context)) return;
    await _player.pause();
    _setPlaying(false);
    if (!mounted) return;
    startCreate(context, CreateKind.story, sound: widget.sound);
  }

  // ───────────────────────── الواجهة ─────────────────────────

  Widget _disc(AppPalette colors) {
    final s = widget.sound;
    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox(
        width: 104,
        height: 104,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _spin,
              child: Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                      colors: [Color(0xFF3A3A3A), Color(0xFF0B0B0B)]),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: ClipOval(
                  child: UserAvatar(
                      uid: s.uid, fallbackName: s.username, radius: 26),
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0x88000000)),
              child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette colors) {
    final s = widget.sound;
    final total = _uses + (_original != null ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              _disc(colors),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(soundTitle(s),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => openProfile(context, s.uid),
                      child: Text('@${s.username}',
                          style: TextStyle(
                              color: colors.textDim,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        _headLoaded
                            ? trf('{0} فيديو', [_compact(total)])
                            : '',
                        style:
                            TextStyle(color: colors.textDim, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _useSound,
                  icon: const Icon(Icons.videocam_rounded, size: 20),
                  label: Text(tr('استخدام الصوت'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _postToStory,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: Text(tr('نشر إلى قصة'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<bool>(
            stream: _saved,
            builder: (context, snap) {
              final saved = snap.data ?? false;
              return SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _toggleSave(saved),
                  icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20),
                  label: Text(saved ? tr('محفوظ') : tr('حفظ')),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(Post post, List<Post> all) {
    return GestureDetector(
      onTap: () {
        _player.pause();
        _setPlaying(false);
        showShortDialog(context, post, shorts: all);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (post.video != null) VideoCover(source: post.video!),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x99000000), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_arrow_outlined,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(_compact(post.views),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الصوت'))),
      body: SafeArea(
        child: _error != null && !_headLoaded
            ? ErrorState(
                error: _error, title: tr('تعذر التحميل'), onRetry: _loadHead)
            : CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _header(colors)),
                  if (_headLoaded && all.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                          icon: Icons.music_off_rounded,
                          title: tr('لا توجد فيديوهات بهذا الصوت بعد'),
                          message: tr('كن أول من يستخدمه.')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(2),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 9 / 16,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _tile(all[i], all),
                          childCount: all.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// «الأصوات المحفوظة» (تُفتح من الإعدادات).
class SavedSoundsScreen extends StatelessWidget {
  const SavedSoundsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الأصوات المحفوظة'))),
      body: SafeArea(
        child: StreamBuilder<List<PostSound>>(
          stream: SoundService.savedSounds(),
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorState(error: snap.error, title: tr('تعذر التحميل'));
            }
            if (!snap.hasData) return const AppLoading();
            final list = snap.data!;
            if (list.isEmpty) {
              return EmptyState(
                  icon: Icons.music_note_rounded,
                  title: tr('لا توجد أصوات محفوظة'),
                  message: tr('افتح قرص الصوت في أي فيديو واضغط حفظ.'));
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: colors.text.withOpacity(0.08)),
              itemBuilder: (_, i) {
                final s = list[i];
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(9),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                            colors: [Color(0xFF3A3A3A), Color(0xFF0B0B0B)])),
                    child: ClipOval(
                        child: UserAvatar(
                            uid: s.uid, fallbackName: s.username, radius: 12)),
                  ),
                  title: Text(soundTitle(s)),
                  subtitle: Text('@${s.username}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.bookmark_rounded),
                    tooltip: tr('إلغاء الحفظ'),
                    onPressed: () => SoundService.toggleSave(s, true),
                  ),
                  onTap: () => openSound(context, s),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
