import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';
import '../theme.dart';
import '../web_trim.dart';

enum CreateKind { post, story, reel }

/// حدود الرفع للحفاظ على مجانية الخدمة.
const maxVideoSeconds = 60;
const maxSourceBytes =
    300 * 1024 * 1024; // أقصى حجم أصلي يمكن قصّه داخل المتصفح
// في وضع التجربة (Firestore) الحدود أصغر حفاظاً على الحصة المجانية.
int get maxVideoBytes =>
    PostService.useStorage ? 40 * 1024 * 1024 : 15 * 1024 * 1024;
int get maxPhotoBytes =>
    PostService.useStorage ? 5 * 1024 * 1024 : 3 * 1024 * 1024;

String _kindTitle(CreateKind k) => switch (k) {
      CreateKind.post => 'منشور جديد',
      CreateKind.story => 'قصة جديدة',
      CreateKind.reel => 'ريلز جديد',
    };

/// يفتح شاشة الإنشاء (كاميرا أو ملفات الجهاز) للنوع المطلوب.
void startCreate(BuildContext context, CreateKind kind, {Post? sound}) {
  Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CaptureScreen(kind: kind, sound: sound)));
}

/// الشريط السفلي الصغير: منشور / قصة / ريلز (مثل إنستغرام).
void showCreateSheet(BuildContext context) {
  final colors = context.appColors;
  showModalBottomSheet(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget tile(IconData icon, String title, CreateKind kind) => ListTile(
            leading: Icon(icon, size: 26, color: colors.textDim),
            title: Text(
              title,
              style: TextStyle(
                  fontSize: 16,
                  color: colors.text,
                  fontWeight: FontWeight.w600),
            ),
            onTap: () {
              final navigator = Navigator.of(ctx);
              navigator.pop();
              navigator.push<void>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => CaptureScreen(kind: kind),
                ),
              );
            },
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: colors.textDim,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('إنشاء',
                  style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            Divider(height: 1, color: colors.text.withOpacity(0.12)),
            tile(Icons.grid_on_rounded, 'منشور', CreateKind.post),
            tile(Icons.add_circle_outline_rounded, 'قصة', CreateKind.story),
            tile(Icons.movie_creation_outlined, 'ريلز', CreateKind.reel),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class PickedMedia {
  final Uint8List bytes;
  final String ext;
  final String mime;
  final String name;
  final bool isVideo;
  final bool trimmed;
  PickedMedia(
      {required this.bytes,
      required this.ext,
      required this.mime,
      required this.name,
      required this.isVideo,
      this.trimmed = false});
}

class MediaError implements Exception {
  final String message;
  MediaError(this.message);
}

/// مدة الفيديو بالثواني، أو null إن تعذرت قراءته.
Future<int?> _videoSeconds(XFile f) async {
  final vc = VideoPlayerController.networkUrl(Uri.parse(f.path));
  try {
    await vc.initialize();
    return vc.value.duration.inSeconds;
  } catch (_) {
    return null;
  } finally {
    await vc.dispose();
  }
}

/// يختار فيديو/صورة من الكاميرا أو ملفات الجهاز، مع القص والضغط والتحقق من الحجم.
Future<PickedMedia?> pickMedia(
  ImagePicker picker, {
  required bool video,
  required ImageSource source,
  bool tall = false,
  void Function(bool)? onTrimming,
}) async {
  if (video) {
    final f = await picker.pickVideo(
        source: source, maxDuration: const Duration(seconds: maxVideoSeconds));
    if (f == null) return null;
    final dot = f.name.lastIndexOf('.');
    var ext = dot > 0 ? f.name.substring(dot + 1).toLowerCase() : 'mp4';
    final secs = await _videoSeconds(f);
    if (secs == null) throw MediaError('تعذر قراءة الفيديو. جرّب صيغة MP4.');
    if (await f.length() > maxSourceBytes) {
      throw MediaError(
          'الملف كبير جداً للمعالجة داخل المتصفح (الحد ${maxSourceBytes ~/ (1024 * 1024)}MB).');
    }

    Uint8List bytes;
    var trimmed = false;
    if (secs > maxVideoSeconds) {
      // الفيديو أطول من دقيقة: نقصّه تلقائياً إلى أول 60 ثانية.
      onTrimming?.call(true);
      try {
        bytes = await trimVideo(f.path, ext, maxVideoSeconds);
        ext = 'mp4';
        trimmed = true;
      } catch (e) {
        throw MediaError('تعذر قص الفيديو تلقائياً: $e');
      } finally {
        onTrimming?.call(false);
      }
    } else {
      bytes = await f.readAsBytes();
    }

    if (bytes.length > maxVideoBytes) {
      throw MediaError(
          'حجم الفيديو بعد المعالجة ${(bytes.length / (1024 * 1024)).toStringAsFixed(0)}MB والحد ${maxVideoBytes ~/ (1024 * 1024)}MB. صوّره بجودة أقل (مثل 720p).');
    }
    if (ext == 'mov') ext = 'quicktime';
    return PickedMedia(
        bytes: bytes,
        ext: ext,
        mime: 'video/$ext',
        name: f.name,
        isVideo: true,
        trimmed: trimmed);
  }

  // الصور تُضغط داخل المتصفح (تصغير الأبعاد + جودة 60%) قبل الرفع.
  final f = await picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: tall ? 1920 : 1080,
      imageQuality: 60);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > maxPhotoBytes) throw MediaError('الصورة كبيرة جداً');
  return PickedMedia(
      bytes: bytes,
      ext: 'jpg',
      mime: 'image/jpeg',
      name: f.name,
      isVideo: false);
}

/// الخطوة الأولى: اختيار المصدر (كاميرا أو ملفات الجهاز) كما في إنستغرام.
class CaptureScreen extends StatefulWidget {
  final CreateKind kind;
  final Post? sound;
  const CaptureScreen({super.key, required this.kind, this.sound});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  bool _storyVideo = false;
  bool _trimming = false;
  bool _busy = false;
  String? _error;

  bool get _video =>
      widget.kind == CreateKind.reel ||
      (widget.kind == CreateKind.story && _storyVideo);

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final media = await pickMedia(
        _picker,
        video: _video,
        source: source,
        tall: widget.kind == CreateKind.story,
        onTrimming: (b) {
          if (mounted) setState(() => _trimming = b);
        },
      );
      if (media == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ComposeScreen(
              kind: widget.kind, media: media, sound: widget.sound)));
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر فتح الكاميرا أو الملفات: $e');
    } finally {
      if (mounted && !_trimming) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 28)),
                  Expanded(
                      child: Text(_kindTitle(kind),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.text,
                              fontSize: 17, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _trimming
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.accent),
                          SizedBox(height: 12),
                          Text('الفيديو أطول من دقيقة، جارٍ قصّه تلقائياً...',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.text)),
                          Text('قد يستغرق ذلك لحظات',
                              style: TextStyle(
                                  color: colors.textDim,
                                  fontSize: 12)),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [
                                    AppColors.accent,
                                    AppColors.accent2
                                  ])),
                              child: Icon(
                                  _video
                                      ? Icons.videocam_rounded
                                      : Icons.photo_camera_rounded,
                                  size: 52,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _video
                                  ? 'صوّر فيديو (حتى دقيقة) أو اختر من ملفاتك'
                                  : 'التقط صورة أو اختر من ملفاتك',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16, color: colors.text),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: colors.text)),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            if (kind == CreateKind.story)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                        label: const Text('صورة'),
                        selected: !_storyVideo,
                        onSelected: (_) => setState(() => _storyVideo = false)),
                    const SizedBox(width: 10),
                    ChoiceChip(
                        label: const Text('فيديو'),
                        selected: _storyVideo,
                        onSelected: (_) => setState(() => _storyVideo = true)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _sideButton(Icons.photo_library_rounded, 'ملفات الجهاز',
                      () => _pick(ImageSource.gallery)),
                  GestureDetector(
                    onTap: () => _pick(ImageSource.camera),
                    child: Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.text, width: 4)),
                      child: Container(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _video ? AppColors.accent2 : Colors.white),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3))
                            : null,
                      ),
                    ),
                  ),
                  kind == CreateKind.post
                      ? _sideButton(Icons.edit_note_rounded, 'نص فقط', () {
                          Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => ComposeScreen(kind: kind)));
                        })
                      : const SizedBox(width: 72),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: context.appColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.appColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// الخطوة الثانية: معاينة + كتابة النص + مشاركة.
class ComposeScreen extends StatefulWidget {
  final CreateKind kind;
  final PickedMedia? media; // null = منشور نصي فقط
  final Post? sound;
  const ComposeScreen({super.key, required this.kind, this.media, this.sound});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _caption = TextEditingController();
  double _progress = 0;
  bool _busy = false;
  String? _error;

  bool get _textOnly => widget.media == null;

  String get _hint => switch (widget.kind) {
        CreateKind.post =>
          _textOnly ? 'بماذا تفكر؟ أضف #هاشتاق' : 'اكتب وصفاً...',
        CreateKind.story => 'أضف نصاً للقصة (اختياري)',
        CreateKind.reel => 'اكتب وصفاً مع #هاشتاقات',
      };

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (_textOnly && caption.isEmpty) {
      setState(() => _error = 'اكتب شيئاً أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      void onProgress(double p) {
        if (mounted) setState(() => _progress = p);
      }

      final m = widget.media;
      if (m == null) {
        await PostService.publishText(caption);
      } else {
        final type = switch (widget.kind) {
          CreateKind.post => PostType.photo,
          CreateKind.story => PostType.story,
          CreateKind.reel => PostType.video,
        };
        await PostService.publishMedia(type, m.bytes,
            mime: m.mime,
            ext: m.ext,
            caption: caption,
            onProgress: onProgress,
            soundPostId: widget.sound?.id,
            soundUsername: widget.sound?.username);
      }
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(widget.kind == CreateKind.story
              ? 'تمت إضافة القصة'
              : 'تم النشر بنجاح')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'فشل النشر: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    return Scaffold(
      appBar: AppBar(
        title: Text(_kindTitle(widget.kind)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _publish,
            child: Text(
              widget.kind == CreateKind.story ? 'إضافة' : 'مشاركة',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (m != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child: m.isVideo
                        ? _VideoPreview(bytes: m.bytes, mime: m.mime)
                        : Image.memory(m.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            if (m != null && m.trimmed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'تم قصّ الفيديو إلى أول 60 ثانية',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: context.appColors.textDim, fontSize: 12),
                ),
              ),
            if (widget.sound != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text('الصوت الأصلي - @${widget.sound!.username}'),
                  subtitle: const Text('سيُضاف هذا الصوت إلى الفيديو المنشور'),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              minLines: _textOnly ? 6 : 3,
              maxLines: _textOnly ? 12 : 5,
              maxLength: 500,
              decoration: InputDecoration(hintText: _hint),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!,
                    style: TextStyle(color: context.appColors.text)),
              ),
            if (_busy && !_textOnly) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 4),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _publish,
              child: Text(widget.kind == CreateKind.story
                  ? 'إضافة إلى قصتك'
                  : 'مشاركة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final Uint8List bytes;
  final String mime;
  const _VideoPreview({required this.bytes, required this.mime});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final vc = VideoPlayerController.networkUrl(
          Uri.parse(makeBlobUrl(widget.bytes, widget.mime)));
      await vc.initialize();
      await vc.setLooping(true);
      await vc.setVolume(0);
      await vc.play();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      setState(() => _vc = vc);
    } catch (_) {}
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    if (vc == null)
      return const SizedBox(
          height: 240, child: Center(child: CircularProgressIndicator()));
    return GestureDetector(
      onTap: () => setState(() => vc.value.isPlaying ? vc.pause() : vc.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
              aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc)),
          if (!vc.value.isPlaying)
            const Icon(Icons.play_arrow_rounded,
                size: 72, color: Colors.white70),
        ],
      ),
    );
  }
}
