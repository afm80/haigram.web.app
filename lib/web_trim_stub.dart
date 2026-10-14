import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// نسخة غير الويب (أندرويد): رابط data بدل blob.
String makeBlobUrl(Uint8List bytes, String mime) =>
    'data:$mime;base64,${base64Encode(bytes)}';

/// على غير الويب لا يوجد قص: يُرجع الملف كما هو.
Future<Uint8List> trimVideo(String path, String ext, int seconds) =>
    File(path).readAsBytes();

/// على غير الويب لا يوجد ضغط: يُرجع الملف كما هو.
Future<Uint8List> compressVideo(
  String path,
  String ext, {
  required int seconds,
  int maxShortSide = 720,
  void Function(double)? onProgress,
}) =>
    File(path).readAsBytes();

/// على غير الويب لا تُولَّد صورة مصغّرة.
Future<Uint8List?> videoThumbnail(String path, {int width = 320}) async => null;
