import 'dart:async';

import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'post_widgets.dart';
import 'story_widgets.dart';

/// الرئيسية: شريط القصص ثم منشورات المستخدمين وأحداثهم (صور ونصوص) بالأحدث.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  late final Stream<List<Post>> _feed = _latestPosts();

  /// الصور والنصوص في قائمة واحدة مرتبة بالأحدث.
  Stream<List<Post>> _latestPosts() {
    late final StreamController<List<Post>> controller;
    final subs = <StreamSubscription<List<Post>>>[];
    List<Post>? photos;
    List<Post>? texts;

    void emit() {
      final p = photos;
      final t = texts;
      if (p == null || t == null) return;
      controller.add([...p, ...t]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }

    controller = StreamController<List<Post>>(
      onListen: () {
        subs.add(PostService.stream(PostType.photo, limit: 15).listen((v) {
          photos = v;
          emit();
        }, onError: controller.addError));
        subs.add(PostService.stream(PostType.text, limit: 15).listen((v) {
          texts = v;
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Post>>(
        stream: _feed,
        builder: (context, snap) {
          final all = snap.data;
          // شورتز تظهر في شريط أفقي، والبقية منشورات عادية.
          final shorts = [
            for (final p in all ?? const <Post>[])
              if (p.isShort) p
          ];
          final posts =
              all == null ? null : [for (final p in all) if (!p.isShort) p];
          final hasPosts = posts != null && posts.isNotEmpty;
          // الشريط بعد 5 منشورات (أو في النهاية إن كانت أقل).
          final shortsAt = hasPosts ? (posts.length < 5 ? posts.length : 5) : 0;
          final hasShorts = shorts.isNotEmpty;
          final rows = hasPosts ? posts.length + 1 : (hasShorts ? 1 : 2);
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: rows + (hasShorts ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Column(children: [
                  const StoriesBar(),
                  Divider(
                      height: 1,
                      color: context.appColors.text.withOpacity(0.12)),
                ]);
              }
              if (hasShorts && i == shortsAt + 1) {
                return ShortsRow(shorts: shorts);
              }
              final idx = (hasShorts && i > shortsAt + 1) ? i - 1 : i;
              if (hasPosts) return PostCard(post: posts[idx - 1]);
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text('تعذر تحميل المنشورات\n${snap.error}',
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
