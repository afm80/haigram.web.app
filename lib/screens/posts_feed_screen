import 'dart:async';

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import 'post_widgets.dart';

/// صفحة المنشورات: ألبومات صور ومنشورات نصية، مع تبويب "من أتابعهم".
class PostsFeedScreen extends StatelessWidget {
  const PostsFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            const TabBar(tabs: [Tab(text: 'للجميع'), Tab(text: 'من أتابعهم')]),
            const Expanded(
              child: TabBarView(children: [_FeedList(onlyFollowing: false), _FeedList(onlyFollowing: true)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  final bool onlyFollowing;
  const _FeedList({required this.onlyFollowing});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: onlyFollowing ? PostService.followingIds() : Stream.value(const []),
      builder: (context, followSnap) {
        final following = followSnap.data ?? const [];
        return StreamBuilder<List<Post>>(
          stream: _merge(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('تعذر التحميل\n${snap.error}', textAlign: TextAlign.center));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var list = snap.data!;
            if (onlyFollowing) list = list.where((p) => following.contains(p.uid)).toList();
            if (list.isEmpty) {
              return Center(child: Text(onlyFollowing ? 'تابع أشخاصاً لتظهر منشوراتهم هنا' : 'لا توجد منشورات بعد'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) => PostCard(post: list[i]),
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
