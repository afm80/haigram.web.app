import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/post_service.dart';
import '../theme.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
  if (d.inHours < 24) return 'قبل ${d.inHours} س';
  return 'قبل ${d.inDays} يوم';
}

/// بطاقة منشور (صور أو نص أو نتيجة بحث) لصفحة المنشورات.
class PostCard extends StatelessWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.accent,
              child: Text(post.username.isNotEmpty ? post.username[0].toUpperCase() : '?'),
            ),
            title: Text(post.username, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(timeAgo(post.createdAt), style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            trailing: post.type == PostType.video ? const Icon(Icons.videocam_rounded, color: AppColors.textDim) : null,
          ),
          if (post.type == PostType.photo) PostImage(post: post),
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(post.caption, style: const TextStyle(fontSize: 16, height: 1.5)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                StreamBuilder<bool>(
                  stream: PostService.isLiked(post.id),
                  builder: (context, s) {
                    final liked = s.data ?? false;
                    return TextButton.icon(
                      onPressed: () => PostService.toggleLike(post.id, liked),
                      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? AppColors.accent2 : AppColors.textDim),
                      label: Text('${post.likes}', style: const TextStyle(color: AppColors.textDim)),
                    );
                  },
                ),
                StreamBuilder<bool>(
                  stream: PostService.isSaved(post.id),
                  builder: (context, s) {
                    final saved = s.data ?? false;
                    return IconButton(
                      onPressed: () => PostService.toggleSave(post.id, saved),
                      icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: saved ? AppColors.accent : AppColors.textDim),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صورة منشور: من رابط Storage أو من Firestore (وضع التجربة).
class PostImage extends StatelessWidget {
  final Post post;
  final BoxFit fit;
  final double? height;
  const PostImage({super.key, required this.post, this.fit = BoxFit.cover, this.height});

  @override
  Widget build(BuildContext context) {
    final loading = SizedBox(height: height ?? 240, child: const Center(child: CircularProgressIndicator()));
    final broken = SizedBox(height: height ?? 120, child: const Icon(Icons.broken_image_outlined));
    if (post.mediaUrl != null) {
      return CachedNetworkImage(
        imageUrl: post.mediaUrl!,
        width: double.infinity,
        height: height,
        fit: fit,
        placeholder: (_, __) => loading,
        errorWidget: (_, __, ___) => broken,
      );
    }
    if (post.mediaId == null) return broken;
    return FutureBuilder<Uint8List>(
      future: PostService.mediaBytes(post),
      builder: (_, s) {
        if (s.hasError) return broken;
        if (!s.hasData) return loading;
        return Image.memory(s.data!, width: double.infinity, height: height, fit: fit, gaplessPlayback: true);
      },
    );
  }
}
