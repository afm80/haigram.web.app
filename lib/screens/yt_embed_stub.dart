// مشغّل يوتيوب لتطبيق أندرويد/آيفون (عبر حزمة youtube_player_iframe).
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

Widget buildYoutubeEmbed(String videoId, {double aspect = 16 / 9}) =>
    _NativeYoutube(videoId: videoId, aspect: aspect);

class _NativeYoutube extends StatefulWidget {
  final String videoId;
  final double aspect;
  const _NativeYoutube({required this.videoId, this.aspect = 16 / 9});

  @override
  State<_NativeYoutube> createState() => _NativeYoutubeState();
}

class _NativeYoutubeState extends State<_NativeYoutube> {
  late final YoutubePlayerController _controller =
      YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(showFullscreenButton: true),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      YoutubePlayer(controller: _controller, aspectRatio: widget.aspect);
}
