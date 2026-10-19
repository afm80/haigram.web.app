import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_gate.dart';
import '../services/post_service.dart';
import '../theme.dart';

import '../l10n.dart';
import '../net_error.dart';

enum CreateKind { post, story, video }

/// حدود الرفع للحفاظ على مجانية الخدمة.
// الصور تُصغَّر عند الاختيار (1080px وجودة 60%) فتبقى غالباً أقل من 500KB.
int get maxPhotoBytes =>
    PostService.useRemoteMedia ? 3 * 1024 * 1024 : 3 * 1024 * 1024;

String _kindTitle(CreateKind k) => switch (k) {
      CreateKind.post => tr('منشور جديد'),
      CreateKind.story => tr('قصة جديدة'),
      CreateKind.video => tr('فيديو جديد'),
    };

/// يفتح شاشة الإنشاء (كاميرا أو ملفات الجهاز) للنوع المطلوب.
void startCreate(BuildContext context, CreateKind kind) {
  if (needsLogin(context)) return;
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => kind == CreateKind.video
          ? ComposeScreen(kind: kind)
          : CaptureScreen(kind: kind)));
}

/// الشريط السفلي الصغير: منشور / قصة (مثل إنستغرام).
void showCreateSheet(BuildContext context) {
  if (needsLogin(context)) return;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      final colors = ctx.appColors;

      void open(CreateKind kind) {
        final navigator = Navigator.of(ctx);
        navigator.pop();
        navigator.push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => kind == CreateKind.video
                ? ComposeScreen(kind: kind)
                : CaptureScreen(kind: kind),
          ),
        );
      }

      Widget option({
        required String title,
        required IconData icon,
        required CreateKind kind,
      }) =>
          SizedBox(
            width: 88,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => open(kind),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: colors.surfaceHigh,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon, color: colors.text, size: 26),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

      return SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textDim.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      tr('إنشاء'),
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    PositionedDirectional(
                      end: 8,
                      child: IconButton(
                        tooltip: tr('إغلاق'),
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded,
                            color: colors.text, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.text.withOpacity(0.10)),
              SizedBox(
                height: 104,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      option(
                        title: tr('منشور'),
                        icon: Icons.grid_on_outlined,
                        kind: CreateKind.post,
                      ),
                      option(
                        title: tr('قصة'),
                        icon: Icons.add_circle_outline_rounded,
                        kind: CreateKind.story,
                      ),
                      option(
                        title: tr('فيديو'),
                        icon: Icons.movie_creation_outlined,
                        kind: CreateKind.video,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
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
  PickedMedia(
      {required this.bytes,
      required this.ext,
      required this.mime,
      required this.name});
}

class MediaError implements Exception {
  final String message;
  MediaError(this.message);
}

/// يختار صورة من الكاميرا أو ملفات الجهاز، مع التصغير والتحقق من الحجم.
Future<PickedMedia?> pickMedia(
  ImagePicker picker, {
  required ImageSource source,
  bool tall = false,
}) async {
  // الصور تُضغط داخل المتصفح (تصغير الأبعاد + جودة 60%) قبل الرفع.
  final f = await picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: tall ? 1920 : 1080,
      imageQuality: 60);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > maxPhotoBytes) throw MediaError(tr('الصورة كبيرة جداً'));
  return PickedMedia(
      bytes: bytes, ext: 'jpg', mime: 'image/jpeg', name: f.name);
}

/// يختار عدة صور دفعة واحدة (حتى [max]) من ملفات الجهاز لألبوم.
/// [truncated] يصبح true إن اختار المستخدم أكثر من الحد فقُصّت القائمة.
Future<(List<PickedMedia>, bool)> pickAlbumMedia(
  ImagePicker picker, {
  int max = PostService.maxAlbumImages,
}) async {
  if (max <= 0) return (<PickedMedia>[], false);
  final files = await picker.pickMultiImage(
      maxWidth: 1080, maxHeight: 1080, imageQuality: 60);
  final out = <PickedMedia>[];
  for (final f in files.take(max)) {
    final bytes = await f.readAsBytes();
    if (bytes.length > maxPhotoBytes) {
      throw MediaError(tr('إحدى الصور كبيرة جداً'));
    }
    out.add(PickedMedia(
        bytes: bytes, ext: 'jpg', mime: 'image/jpeg', name: f.name));
  }
  return (out, files.length > max);
}

/// الخطوة الأولى: اختيار المصدر (كاميرا أو ملفات الجهاز) كما في إنستغرام.
class CaptureScreen extends StatefulWidget {
  final CreateKind kind;
  const CaptureScreen({super.key, required this.kind});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // منشور من ملفات الجهاز: اختيار عدة صور لألبوم (يتطلب تخزيناً برابط).
      if (source == ImageSource.gallery &&
          widget.kind == CreateKind.post &&
          PostService.useRemoteMedia) {
        final (picked, truncated) = await pickAlbumMedia(_picker);
        if (picked.isEmpty || !mounted) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        if (truncated) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(trf('الحد الأقصى {0} صور، تم أخذ أول {1}',
                  [PostService.maxAlbumImages, PostService.maxAlbumImages]))));
        }
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ComposeScreen(
                kind: widget.kind,
                media: picked.first,
                extraMedia: picked.sublist(1))));
        return;
      }
      final media = await pickMedia(
        _picker,
        source: source,
        tall: widget.kind == CreateKind.story,
      );
      if (media == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ComposeScreen(kind: widget.kind, media: media)));
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted)
        setState(() => _error =
            friendlyError(e, fallback: tr('تعذر فتح الكاميرا أو الملفات')));
    } finally {
      if (mounted) setState(() => _busy = false);
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
                              fontSize: 17,
                              fontWeight: FontWeight.w700))),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                                colors: [AppColors.accent, AppColors.accent2])),
                        child: const Icon(Icons.photo_camera_rounded,
                            size: 52, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        (kind == CreateKind.post && PostService.useRemoteMedia)
                            ? trf('التقط صورة أو اختر حتى {0} صور من ملفاتك',
                                [PostService.maxAlbumImages])
                            : tr('التقط صورة أو اختر من ملفاتك'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: colors.text),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.text)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _sideButton(Icons.photo_library_rounded, tr('ملفات الجهاز'),
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
                            shape: BoxShape.circle, color: Colors.white),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
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
  final List<PickedMedia> extraMedia; // صور إضافية لألبوم (بعد الأولى)
  const ComposeScreen(
      {super.key, required this.kind, this.media, this.extraMedia = const []});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _caption = TextEditingController();
  final _videoLink = TextEditingController();
  double _progress = 0;
  bool _busy = false;
  String? _error;
  final _picker = ImagePicker();

  // صور المنشور (واحدة أو ألبوم). تتغيّر بالإضافة والحذف قبل النشر.
  late final List<PickedMedia> _images = [
    if (widget.media != null) widget.media!,
    ...widget.extraMedia,
  ];

  bool get _textOnly => widget.media == null;

  // الألبومات للمنشور فقط (لا للقصة) وتتطلب تخزيناً برابط مباشر.
  bool get _canAlbum =>
      widget.kind == CreateKind.post && PostService.useRemoteMedia;

  Future<void> _addMore() async {
    final room = PostService.maxAlbumImages - _images.length;
    if (room <= 0 || _busy) return;
    try {
      final (picked, truncated) = await pickAlbumMedia(_picker, max: room);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _images.addAll(picked);
        _error = truncated
            ? trf('الحد الأقصى {0} صور', [PostService.maxAlbumImages])
            : null;
      });
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted)
        setState(
            () => _error = friendlyError(e, fallback: tr('تعذر اختيار الصور')));
    }
  }

  // رابط يوتيوب متاح في المنشور النصي فقط (نص، أو فيديو، أو الاثنان معاً).
  bool get _isVideoKind => widget.kind == CreateKind.video;
  bool get _allowVideo => _textOnly && _isVideoKind;

  @override
  void dispose() {
    _caption.dispose();
    _videoLink.dispose();
    super.dispose();
  }

  String get _hint => switch (widget.kind) {
        CreateKind.post =>
          _textOnly ? tr('بماذا تفكر؟ أضف #هاشتاق') : tr('اكتب وصفاً...'),
        CreateKind.story => tr('أضف نصاً للقصة (اختياري)'),
        CreateKind.video => tr('أضف وصفاً للفيديو (اختياري)'),
      };

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (_textOnly && !_isVideoKind) {
      setState(() => _error = tr('أضف صورة أو رابط فيديو أولاً'));
      return;
    }
    final link = _allowVideo ? _videoLink.text.trim() : '';
    String? videoId;
    if (link.isNotEmpty) {
      videoId = PostService.youtubeId(link);
      if (videoId == null) {
        setState(() => _error = tr('رابط يوتيوب غير صالح'));
        return;
      }
    }
    if (_isVideoKind && videoId == null) {
      setState(() => _error = tr('أضف رابط فيديو يوتيوب أولاً'));
      return;
    }
    if (_textOnly && caption.isEmpty && videoId == null) {
      setState(() => _error = tr('اكتب شيئاً أو أضف رابط فيديو أولاً'));
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

      final m = _images.isEmpty ? null : _images.first;
      if (m == null) {
        await PostService.publishText(caption,
            videoId: videoId,
            isShort: videoId != null && PostService.isShortsLink(link));
      } else {
        final type = switch (widget.kind) {
          CreateKind.post => PostType.photo,
          CreateKind.story => PostType.story,
          CreateKind.video => PostType.photo,
        };
        if (_images.length > 1 && type == PostType.photo) {
          await PostService.publishAlbum([for (final img in _images) img.bytes],
              mime: m.mime,
              ext: m.ext,
              caption: caption,
              onProgress: onProgress);
        } else {
          await PostService.publishMedia(type, m.bytes,
              mime: m.mime,
              ext: m.ext,
              caption: caption,
              onProgress: onProgress);
        }
      }
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(widget.kind == CreateKind.story
              ? tr('تمت إضافة القصة')
              : tr('تم النشر بنجاح'))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, fallback: tr('فشل النشر'));
        });
      }
    }
  }

  /// شريط معاينة الألبوم: مصغّرات أفقية، وعلى كل واحدة زر حذف.
  Widget _albumStrip() {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_images[i].bytes,
                  width: 120, height: 150, fit: BoxFit.cover),
            ),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: GestureDetector(
                onTap: _busy ? null : () => setState(() => _images.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: 4,
              start: 6,
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black87)])),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_kindTitle(widget.kind)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _publish,
            child: Text(
              widget.kind == CreateKind.story ? tr('إضافة') : tr('مشاركة'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_images.length == 1)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5),
                    child:
                        Image.memory(_images.first.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            if (_images.length > 1) _albumStrip(),
            if (_images.isNotEmpty &&
                _canAlbum &&
                _images.length < PostService.maxAlbumImages)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addMore,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(trf('إضافة صور ({0}/{1})',
                      [_images.length, PostService.maxAlbumImages])),
                ),
              ),
            const SizedBox(height: 16),
            if (_allowVideo) ...[
              TextField(
                controller: _videoLink,
                autofocus: _isVideoKind,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: _isVideoKind
                      ? tr('الصق رابط فيديو يوتيوب')
                      : tr('رابط فيديو يوتيوب (اختياري)'),
                  prefixIcon: const Icon(Icons.play_circle_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                  // مع Cloudinary لا توجد نسبة تقدم فعلية، فنعرض شريطاً متحركاً.
                  value: _progress > 0 ? _progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 4),
              Text(
                  _progress > 0
                      ? '${(_progress * 100).toStringAsFixed(0)}%'
                      : tr('جارٍ الرفع...'),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _publish,
              child: Text(widget.kind == CreateKind.story
                  ? tr('إضافة إلى قصتك')
                  : tr('مشاركة')),
            ),
          ],
        ),
      ),
    );
  }
}
