import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'story_widgets.dart';

/// يزداد عند الضغط على أيقونة الرئيسية وأنت فيها: تمرير للأعلى وتحديث.
final ValueNotifier<int> homeRefreshTick = ValueNotifier<int>(0);

/// الرئيسية: شريط القصص ثم منشورات المستخدمين بالأحدث، وتُحمَّل دفعات عند التمرير.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  late Stream<List<Post>> _shortsFeed = _allShorts();
  final ScrollController _scroll = ScrollController();

  // التحميل على دفعات: صور ونصوص كل منها بمؤشره الخاص.
  List<Post>? _photos;
  List<Post>? _texts;
  DocumentSnapshot<Map<String, dynamic>>? _photoCursor;
  DocumentSnapshot<Map<String, dynamic>>? _textCursor;
  bool _morePhotos = true;
  bool _moreTexts = true;
  bool _loading = false;
  Object? _error;
  int _gen = 0; // يُلغي نتائج طلب قديم إذا بدأ تحديث جديد

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_refresh);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_refresh);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 600) _load();
  }

  /// تمرير إلى الأعلى ثم إعادة التحميل من الدفعة الأولى (البيانات القديمة تبقى ظاهرة حتى تصل الجديدة).
  void _refresh() {
    if (!mounted) return;
    stopInlineVideos();
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    setState(() => _shortsFeed = _allShorts());
    _load(reset: true);
  }

  /// يجلب الدفعة الأولى ([reset]) أو التالية، ويضيفها إلى القائمة.
  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !(_morePhotos || _moreTexts))) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photoPage = (reset || _morePhotos)
          ? PostService.page(PostType.photo,
              after: reset ? null : _photoCursor)
          : Future<PostPage?>.value(null);
      final textPage = (reset || _moreTexts)
          ? PostService.page(PostType.text, after: reset ? null : _textCursor)
          : Future<PostPage?>.value(null);
      final photos = await photoPage;
      final texts = await textPage;
      if (!mounted || gen != _gen) return;
      setState(() {
        if (photos != null) {
          _photos = _merge(reset ? null : _photos, photos.posts);
          _photoCursor = photos.cursor;
          _morePhotos = photos.hasMore;
        }
        if (texts != null) {
          _texts = _merge(reset ? null : _texts, texts.posts);
          _textCursor = texts.cursor;
          _moreTexts = texts.hasMore;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static List<Post> _merge(List<Post>? old, List<Post> add) {
    final ids = {for (final p in old ?? const <Post>[]) p.id};
    return [...?old, for (final p in add) if (!ids.contains(p.id)) p];
  }

  /// كل الشورتز (حتى 100 من الحسابات العامة) بالأحدث، مستقلة عن قائمة المنشورات
  /// كي يتنقل عارض شورتز بينها كلها وليس بما يظهر في الرئيسية فقط.
  /// نفس استعلام النصوص الحالي (فهرسه موجود) ثم نصفّي شورتز محلياً.
  Stream<List<Post>> _allShorts() =>
      PostService.stream(PostType.text, limit: 100)
          .map((list) => [for (final p in list) if (p.isShort) p]);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Post>>(
        stream: _shortsFeed,
        builder: (context, shortsSnap) {
          final shorts = shortsSnap.data ?? const <Post>[];
          // شورتز تظهر في شريط أفقي، والبقية منشورات عادية.
          final loaded = _photos != null && _texts != null;
          final posts = !loaded
              ? null
              : ([
                  for (final p in [..._photos!, ..._texts!])
                    if (!p.isShort) p
                ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
          final hasPosts = posts != null && posts.isNotEmpty;
          // شريط شورتز في الأعلى مباشرة تحت القصص ليعرف المستخدم بوجوده.
          const shortsAt = 0;
          final hasShorts = shorts.isNotEmpty;
          final rows = hasPosts ? posts.length + 1 : (hasShorts ? 1 : 2);
          final showFooter = hasPosts && _loading;
          final count = rows + (hasShorts ? 1 : 0) + (showFooter ? 1 : 0);
          return ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: count,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Column(children: [
                  const StoriesBar(),
                  Divider(
                      height: 1,
                      color: context.appColors.text.withOpacity(0.12)),
                ]);
              }
              if (showFooter && i == count - 1) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5))),
                );
              }
              if (hasShorts && i == shortsAt + 1) {
                return ShortsRow(shorts: shorts);
              }
              final idx = (hasShorts && i > shortsAt + 1) ? i - 1 : i;
              if (hasPosts) return PostCard(post: posts[idx - 1]);
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text('تعذر تحميل المنشورات\n$_error',
                      textAlign: TextAlign.center),
                );
              }
              if (posts == null) {
                return const SizedBox.shrink();
              }
              return const EmptyState(
                icon: Icons.photo_library_outlined,
                title: 'لا توجد منشورات بعد',
                message: 'شارك أول صورة أو خاطرة مع مجتمعنا.',
              );
            },
          );
        },
      ),
    );
  }
}
