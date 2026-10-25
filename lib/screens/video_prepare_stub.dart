import 'video_prepare_types.dart';

Future<PreparedVideo?> prepareVideoImpl({
  required String blobUrl,
  required int originalSize,
  required int maxSeconds,
  required int keepOriginalBytes,
  void Function(double progress)? onProgress,
}) async =>
    null;

Future<VideoSize?> probeVideoSizeImpl(String blobUrl) async => null;

Future<VideoPoster?> grabVideoPosterImpl(String blobUrl) async => null;
