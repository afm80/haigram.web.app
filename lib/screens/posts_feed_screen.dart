import 'dart:async';

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'create_flow.dart';
import 'post_widgets.dart';
import 'story_widgets.dart';

/// تبويب المنشورات: تجربة إنستغرام (شريط علوي + قصص + منشورات).
class PostsFeedScreen extends StatefulWidget {
  const PostsFeedScreen({super.key});

  @override
  State<PostsFeedScreen> createState() => _PostsFeedScreenState();
}

class _PostsFeedScreenState extends State<PostsFeedScreen> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                PopupMenuButton<bool>(
                  color: AppColors.surfaceHigh,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  onSelected: (v) => setState(() => _following = v),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(value: false, checked: !_following, child: const Text('للجميع')),
                    CheckedPopupMenuItem(value: true, checked: _following, child: const Text('من أتابعهم')),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(colors: [AppColors.accent, AppColors.accent2]).createShader(r),
                        child: const Text('لمحة', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.textDim),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'الكاميرا',
                  onPressed: () => startCreate(context, CreateKind.post),
                  icon: const Icon(Icons.photo_camera_rounded, size: 24),
                ),
                IconButton(
                  tooltip: 'إرسال',
                  onPressed: () {},
                  icon: const Icon(Icons.send_rounded, size: 22),
                ),
              ],
            ),
          ),
          Expanded(child: _FeedList(key: ValueKey(_following), onlyFollowing: _following)),
        ],
      ),
    );
  }
}

class _FeedList extends StatefulWidget {
  final bool onlyFollowing;
  const _FeedList({super.key, required this.onlyFollowing});

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  late final Stream<List<String>> _follow = widget.onlyFollowing ? PostService.followingIds() : Stream.value(const <String>[]);
  late final Stream<List<Post>> _posts = _merge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: _follow,
      builder: (context, followSnap) {
        final following = followSnap.data ?? const <String>[];
        return StreamBuilder<List<Post>>(
          stream: _posts,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('تعذر التحميل\n${snap.error}', textAlign: TextAlign.center));
            if (!snap.hasData) return const AppLoading(message: 'جارٍ تحميل المنشورات...');
            var list = snap.data!;
            if (widget.onlyFollowing) list = list.where((p) => following.contains(p.uid)).toList();
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: list.isEmpty ? 2 : list.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return const Column(children: [StoriesBar(), Divider(height: 1, color: Color(0x22FFFFFF))]);
                }
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.photo_library_outlined,
                    title: widget.onlyFollowing ? 'منشورات أتابعهم ستظهر هنا' : 'لا توجد منشورات بعد',
                    message: widget.onlyFollowing ? 'تابع حسابات لتبقى على اطلاع بآخر صورهم وقصصهم.' : 'شارك أول صورة أو خاطرة مع مجتمع لمحة.',
                  );
                }
                return PostCard(post: list[i - 1]);
              },
            );
          },
        );
      },
    );
  }

  Stream<List<Post>> _merge() async* {
    // نجمع الصور والنصوص في قائمة واحدة مرتبة بالأحدث.
    List<Post> photos = [], texts = [];
    final photoStream = PostService.stream(PostType.photo);
    final textStream = PostService.stream(PostType.text);
    await for (final _ in _zip(photoStream, textStream, (p, t) {
      photos = p;
      texts = t;
    })) {
      yield [...photos, ...texts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  Stream<void> _zip(Stream<List<Post>> a, Stream<List<Post>> b, void Function(List<Post>, List<Post>) onBoth) {
    late StreamController<void> c;
    List<Post>? la, lb;
    final subs = <StreamSubscription>[];
    void emit() {
      if (la != null && lb != null) {
        onBoth(la!, lb!);
        c.add(null);
      }
    }

    c = StreamController<void>(
      onListen: () {
        subs.add(a.listen((v) {
          la = v;
          emit();
        }, onError: c.addError));
        subs.add(b.listen((v) {
          lb = v;
          emit();
        }, onError: c.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return c.stream;
  }
}
