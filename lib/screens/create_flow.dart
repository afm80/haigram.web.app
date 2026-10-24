import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_gate.dart';
import '../services/post_service.dart';
import '../theme.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../video_source.dart';
import 'sticker_sheet.dart' show StickerPanel;
import 'close_friends_screen.dart';
import 'story_mentions.dart';
import 'story_drawing.dart';
import 'story_photo_editor.dart';
import 'story_movable.dart';
import 'story_poll.dart';
import 'story_question.dart';
import 'story_info.dart';
import 'story_slider.dart';
import 'story_stickers.dart';
import 'story_text_editor.dart';
import 'text_story_screen.dart';
import 'post_style.dart';
import 'video_cover.dart';
import 'video_embed_stub.dart' if (dart.library.html) 'video_embed_web.dart';

enum CreateKind { post, story, video }

/// حدود الرفع للحفاظ على مجانية الخدمة.
// الصور تُصغَّر عند الاختيار (1080px وجودة 60%) فتبقى غالباً أقل من 500KB.
int get maxPhotoBytes =>
    PostService.useRemoteMedia ? 3 * 1024 * 1024 : 3 * 1024 * 1024;

String _kindTitle(CreateKind k) => switch (k) {
      CreateKind.post => tr('منشور جديد'),
      CreateKind.story => tr('قصة جديدة'),
      CreateKind.video => tr('رابط فيديو'),
    };

/// يفتح شاشة الإنشاء (كاميرا أو ملفات الجهاز) للنوع المطلوب.
void startCreate(BuildContext context, CreateKind kind) {
  if (needsLogin(context)) return;
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _createScreen(kind)));
}

/// المنشور ورابط الفيديو يبدآن بالنص مباشرة (الصورة اختيارية)، والقصة بالكاميرا.
Widget _createScreen(CreateKind kind) => kind == CreateKind.story
    ? CaptureScreen(kind: kind)
    : ComposeScreen(kind: kind);

/// ورقة زر الإضافة: ثلاث بطاقات أفقية (منشور / قصة / رابط فيديو) مع وصف مختصر لكل واحدة.
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
            builder: (_) => _createScreen(kind),
          ),
        );
      }

      // عنصر أفقي الشكل: أيقونة فوق والاسم تحتها، ويتوزع الثلاثة بالتساوي.
      Widget item(String title, IconData icon, CreateKind kind) => Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => open(kind),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: colors.text, size: 30),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

      return SafeArea(
        top: false,
        child: Material(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 9, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textDim.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr('إنشاء'),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      item(tr('منشور'), Icons.grid_on_rounded, CreateKind.post),
                      item(tr('قصة'), Icons.add_circle_outline_rounded,
                          CreateKind.story),
                      item(tr('رابط فيديو'), Icons.videocam_outlined,
                          CreateKind.video),
                    ],
                  ),
                ),
              ],
            ),
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
  bool tall = false,
}) async {
  if (max <= 0) return (<PickedMedia>[], false);
  final files = await picker.pickMultiImage(
      maxWidth: 1080, maxHeight: tall ? 1920 : 1080, imageQuality: 60);
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

  /// قصة نصية بخلفية ملونة (بدون صورة).
  void _openTextStory() {
    if (_busy) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TextStoryScreen()));
  }

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
      // قصة من ملفات الجهاز: اختيار عدة صور تُنشر كقصص متتالية (مثل إنستغرام).
      if (source == ImageSource.gallery && widget.kind == CreateKind.story) {
        final (picked, truncated) = await pickAlbumMedia(_picker,
            max: ComposeScreen.maxStoryImages, tall: true);
        if (picked.isEmpty || !mounted) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        if (truncated) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(trf('الحد الأقصى {0} صور، تم أخذ أول {1}',
                  [ComposeScreen.maxStoryImages, ComposeScreen.maxStoryImages]))));
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
      if (mounted) {
        setState(() => _error =
            friendlyError(e, fallback: tr('تعذر فتح الكاميرا أو الملفات')));
      }
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
                  widget.kind == CreateKind.story
                      ? _sideButton(Icons.text_fields_rounded, tr('نص'),
                          _openTextStory)
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
  final List<PickedMedia> extraMedia; // صور إضافية لألبوم (بعد الأولى)

  /// أقصى عدد صور تُنشر دفعة واحدة كقصص متتالية.
  static const maxStoryImages = 10;
  const ComposeScreen(
      {super.key, required this.kind, this.media, this.extraMedia = const []});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _caption = TextEditingController();
  final _videoLink = TextEditingController();
  final _scroll = ScrollController();
  final _captureKey = GlobalKey(); // يلتقط الصورة مع ملصقاتها عند النشر
  // ملصقات ونصوص كل صورة على حدة (المفتاح هو كائن الصورة نفسه).
  final Map<PickedMedia, List<StoryStickerItem>> _stickerMap = {};
  // رسم القلم لكل صورة (نقاطه نسبية فيبقى في مكانه).
  final Map<PickedMedia, List<DrawStroke>> _strokeMap = {};
  bool _drawing = false; // وضع الرسم فعّال
  Color _penColor = Colors.white;
  double _penWidth = 0.014;
  bool _erase = false;
  int _cur = 0; // الصورة المعروضة حالياً للتحرير (للقصص المتعددة)
  int _publishedCount = 0; // عدد القصص المنشورة حتى الآن
  bool _extrasSent = false; // أُرسل الاستطلاع والذكر مع أول قصة
  bool _lockScroll = false; // نوقف التمرير أثناء تحريك ملصق
  bool _dialogOpen = false; // نافذة استطلاع/أسئلة مفتوحة: نجمّد حجم الصفحة
  double? _frozenImgH; // ارتفاع الصورة المثبّت أثناء النافذة
  StoryPoll? _poll; // استطلاع القصة (اختياري)
  StoryQuestion? _question; // صندوق أسئلة القصة (اختياري)
  StorySlider? _slider; // شريط إيموجي القصة (اختياري)
  final StoryInfo _info = StoryInfo(); // رابط/موقع/عدّ تنازلي/وقت
  final List<StoryMention> _mentions = []; // مذكورون في القصة (حتى 3)
  bool _closeFriends = false; // القصة للأصدقاء المقربين فقط
  Timer? _linkDebounce;
  VideoSource? _preview; // الفيديو المعروض في المعاينة (رابط صالح)
  String? _linkError; // سبب رفض الرابط، أو فشل تشغيل المعاينة
  bool _playFailed = false; // فشل تشغيل ملف/بث في المعاينة (نعرف النتيجة لهما فقط)
  bool _playOk = false;
  double _progress = 0;
  bool _busy = false;
  String? _error;
  final _picker = ImagePicker();

  // صور المنشور (واحدة أو ألبوم). تتغيّر بالإضافة والحذف قبل النشر.
  late final List<PickedMedia> _images = [
    if (widget.media != null) widget.media!,
    ...widget.extraMedia,
  ];

  bool get _textOnly => _images.isEmpty;

  bool get _isStory => widget.kind == CreateKind.story;

  /// الصورة قيد التحرير حالياً.
  PickedMedia get _curImage {
    if (_cur >= _images.length) _cur = _images.length - 1;
    if (_cur < 0) _cur = 0;
    return _images[_cur];
  }

  /// ملصقات الصورة [m].
  List<StoryStickerItem> _stickersOf(PickedMedia m) =>
      _stickerMap.putIfAbsent(m, () => <StoryStickerItem>[]);

  List<DrawStroke> _strokesOf(PickedMedia m) =>
      _strokeMap.putIfAbsent(m, () => <DrawStroke>[]);

  /// ملصقات الصورة المعروضة الآن.
  List<StoryStickerItem> get _stickers => _stickersOf(_curImage);

  // خلفية ولون النص للمنشور النصي فقط (على طريقة فيسبوك).
  int? _tbg;
  int? _tc;
  bool get _canStyle => widget.kind == CreateKind.post && _textOnly;
  bool get _styled => _canStyle && postBgGradient(_tbg) != null;

  // الألبومات للمنشور فقط (لا للقصة) وتتطلب تخزيناً برابط مباشر.
  bool get _canAlbum =>
      widget.kind == CreateKind.post && PostService.useRemoteMedia;

  // القصة تقبل عدة صور (كل صورة قصة مستقلة) بدون شرط التخزين.
  int get _maxImages =>
      _isStory ? ComposeScreen.maxStoryImages : PostService.maxAlbumImages;

  /// إضافة الصورة الأولى للمنشور (اختيارية): من الكاميرا أو ملفات الجهاز.
  Future<void> _addFirstPhoto(ImageSource source) async {
    if (_busy) return;
    try {
      if (source == ImageSource.gallery && _canAlbum) {
        final (picked, truncated) =
            await pickAlbumMedia(_picker, max: PostService.maxAlbumImages);
        if (!mounted || picked.isEmpty) return;
        setState(() {
          _images.addAll(picked);
          _error = truncated
              ? trf('الحد الأقصى {0} صور', [PostService.maxAlbumImages])
              : null;
        });
      } else {
        final m = await pickMedia(_picker, source: source);
        if (!mounted || m == null) return;
        setState(() {
          _images.add(m);
          _error = null;
        });
      }
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            friendlyError(e, fallback: tr('تعذر فتح الكاميرا أو الملفات')));
      }
    }
  }

  Future<void> _addMore() async {
    final room = _maxImages - _images.length;
    if (room <= 0 || _busy) return;
    try {
      final (picked, truncated) =
          await pickAlbumMedia(_picker, max: room, tall: _isStory);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _images.addAll(picked);
        _error = truncated ? trf('الحد الأقصى {0} صور', [_maxImages]) : null;
      });
    } on MediaError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = friendlyError(e, fallback: tr('تعذر اختيار الصور')));
      }
    }
  }

  // رابط يوتيوب متاح في المنشور النصي فقط (نص، أو فيديو، أو الاثنان معاً).
  bool get _isVideoKind => widget.kind == CreateKind.video;
  bool get _allowVideo => _textOnly && _isVideoKind;

  @override
  void initState() {
    super.initState();
    _videoLink.addListener(_onLinkChanged);
  }

  @override
  void dispose() {
    _linkDebounce?.cancel();
    _caption.dispose();
    _videoLink.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// يحلّل الرابط بعد توقف الكتابة ويعرض المعاينة أو سبب الرفض.
  void _onLinkChanged() {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final text = _videoLink.text.trim();
      final video = text.isEmpty ? null : VideoSource.parse(text);
      final error = text.isEmpty || video != null
          ? null
          : (VideoSource.isFacebookReel(text)
              ? tr('ريلز فيسبوك غير مدعومة. استخدم فيديو فيسبوك عادياً')
              : VideoSource.isUnresolvableShortLink(text)
                  ? tr('هذا رابط مختصر. افتح الفيديو وانسخ رابطه الكامل')
                  : tr('رابط الفيديو غير مدعوم أو غير صالح'));
      // نفس الفيديو: لا نعيد بناء المعاينة.
      if (video?.key == _preview?.key && error == _linkError) return;
      setState(() {
        _preview = video;
        _linkError = error;
        _playFailed = false;
        _playOk = false;
      });
    });
  }

  void _onPreviewResult(bool ok) {
    if (!mounted) return;
    setState(() {
      _playOk = ok;
      _playFailed = !ok;
      _linkError = ok
          ? null
          : tr('تعذر تشغيل هذا الفيديو. تأكد أن الرابط صحيح وعام ويسمح بالتشغيل من المواقع الأخرى');
    });
  }

  /// معاينة الفيديو قبل النشر: يشاهد المستخدم أنه يعمل فعلاً.
  Widget _previewBox(BuildContext context) {
    final v = _preview;
    if (v == null) return const SizedBox.shrink();
    final maxH = MediaQuery.of(context).size.height * (v.isShort ? 0.5 : 0.35);
    final ok = !_playFailed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxH * v.aspect),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _playFailed
                    ? AspectRatio(
                        aspectRatio: v.aspect,
                        child: VideoCover(source: v, showPlay: false))
                    : buildVideoEmbed(v,
                        key: ValueKey('preview-${v.key}'),
                        onResult: _onPreviewResult),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                  ok
                      ? (_playOk
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded)
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: context.appColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _playFailed
                      ? tr('لم يعمل الفيديو. لا يمكن نشره')
                      : _playOk
                          ? trf('الفيديو يعمل ({0})', [v.platformName])
                          : trf('معاينة من {0}: إن لم يظهر الفيديو أو ظهر خطأ فلن يعمل بعد النشر',
                              [v.platformName]),
                  style: TextStyle(
                      color: context.appColors.textDim, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _hint => switch (widget.kind) {
        CreateKind.post =>
          _textOnly ? tr('بماذا تفكر؟ أضف #هاشتاق') : tr('اكتب وصفاً...'),
        CreateKind.story => tr('أضف نصاً للقصة (اختياري)'),
        CreateKind.video => tr('أضف وصفاً للفيديو (اختياري)'),
      };

  // الملصقات للقصة المصوّرة (صورة واحدة) فقط.
  bool get _canSticker => _isStory && _images.isNotEmpty;

  Future<void> _addSticker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) =>
          StickerPanel(onPick: (s) => Navigator.of(ctx).pop(s), height: 320),
    );
    if (emoji == null || !mounted) return;
    setState(() => _stickers.add(StoryStickerItem(emoji)));
  }

  /// كتابة نص فوق صورة القصة.
  Future<void> _addText() async {
    final r = await showStoryTextEditor(context);
    if (r == null || r.text.isEmpty || !mounted) return;
    setState(() =>
        _stickers.add(StoryStickerItem.text(r.text, color: r.color, style: r.style)));
  }

  /// تعديل نص موجود (نص فارغ = حذفه).
  Future<void> _editText(StoryStickerItem it) async {
    final r = await showStoryTextEditor(context, initial: it);
    if (r == null || !mounted) return;
    setState(() {
      if (r.text.isEmpty) {
        _stickers.remove(it);
      } else {
        it.text = r.text;
        it.color = r.color;
        it.style = r.style;
      }
    });
  }

  /// قص الصورة الحالية وتدويرها/قلبها. تبقى ملصقاتها (مواضعها نسبية).
  Future<void> _editPhoto() async {
    if (_busy || _images.isEmpty) return;
    final old = _curImage;
    final out = await editStoryPhoto(context, old.bytes, maxBytes: maxPhotoBytes);
    if (out == null || !mounted) return;
    final fresh =
        PickedMedia(bytes: out, ext: 'jpg', mime: 'image/jpeg', name: old.name);
    setState(() {
      final i = _images.indexOf(old);
      if (i < 0) return;
      _images[i] = fresh;
      final st = _stickerMap.remove(old);
      if (st != null) _stickerMap[fresh] = st;
      final sk = _strokeMap.remove(old);
      if (sk != null) _strokeMap[fresh] = sk;
    });
  }

  Future<double?> _aspectOf(Uint8List bytes) async {
    try {
      final im = await decodeImageFromList(bytes);
      final r = im.width / im.height;
      im.dispose();
      return r;
    } catch (_) {
      return null;
    }
  }

  void _setDialogOpen(bool v) {
    if (!mounted || _dialogOpen == v) return;
    setState(() {
      _dialogOpen = v;
      _frozenImgH =
          v ? MediaQuery.of(context).size.height * 0.5 : null;
    });
  }

  Future<void> _editSlider() async {
    final r = await showSliderDialog(context,
        initial: _slider, onOpen: _setDialogOpen);
    if (r != null && mounted) {
      setState(() => _slider = r.placedLike(_slider, kSliderDefY));
    }
  }

  Future<void> _editQuestion() async {
    final q = await showQuestionDialog(context,
        initial: _question, onOpen: _setDialogOpen);
    if (q != null && mounted) {
      setState(() => _question = q.placedLike(_question, kQuestionDefY));
    }
  }

  Future<void> _editPoll() async {
    final p = await showPollDialog(context,
        initial: _poll, onOpen: _setDialogOpen);
    if (p != null && mounted) {
      setState(() => _poll = p.placedLike(_poll, kPollDefY));
    }
  }

  /// الصورة رقم [index] التي ستُرفع: الأصلية، أو بعد دمج ملصقاتها فيها.
  Future<PickedMedia> _mediaToPublish(int index) async {
    final img = _images[index];
    if (!_canSticker ||
        (_stickersOf(img).isEmpty && _strokesOf(img).isEmpty)) {
      return img;
    }
    // نُنهي وضع الرسم حتى لا تظهر طبقة اللمس في الالتقاط.
    if (_drawing) setState(() => _drawing = false);
    // نعرض هذه الصورة في المعاينة ثم نلتقطها مع ملصقاتها.
    if (_cur != index) setState(() => _cur = index);
    if (_scroll.hasClients && _scroll.offset > 0) {
      await _scroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    Uint8List? bytes;
    try {
      bytes = await bakeStickers(_captureKey, img.bytes,
          maxBytes: maxPhotoBytes);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) {
      throw StateError(tr('تعذر دمج الملصقات، حاول مرة أخرى'));
    }
    return PickedMedia(bytes: bytes, ext: 'jpg', mime: 'image/jpeg', name: img.name);
  }

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (_textOnly && widget.kind == CreateKind.story) {
      setState(() => _error = tr('أضف صورة أولاً'));
      return;
    }
    final link = _allowVideo ? _videoLink.text.trim() : '';
    VideoSource? video;
    if (link.isNotEmpty) {
      video = VideoSource.parse(link);
      if (video == null) {
        setState(() => _error = VideoSource.isFacebookReel(link)
            ? tr('ريلز فيسبوك غير مدعومة. استخدم فيديو فيسبوك عادياً')
            : VideoSource.isUnresolvableShortLink(link)
                ? tr('هذا رابط مختصر. افتح الفيديو وانسخ رابطه الكامل')
                : tr('رابط الفيديو غير مدعوم أو غير صالح'));
        return;
      }
      if (_playFailed) {
        setState(() => _error = tr('لم يعمل الفيديو في المعاينة. لا يمكن نشره'));
        return;
      }
    }
    if (_isVideoKind && video == null) {
      setState(() => _error = tr('أضف رابط فيديو أولاً'));
      return;
    }
    if (_textOnly && caption.isEmpty && video == null) {
      setState(() => _error = tr('اكتب شيئاً أو أضف صورة أولاً'));
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

      if (_textOnly) {
        await PostService.publishText(caption,
            video: video,
            tbg: _canStyle ? _tbg : null,
            tc: _canStyle ? _tc : null);
      } else if (_isStory) {
        // كل صورة تُنشر كقصة مستقلة بالترتيب. الاستطلاع والذكر على أول قصة فقط.
        final total = _images.length + _publishedCount;
        // نسبة عرض الصورة إلى ارتفاعها: ليضع العارض الاستطلاع في مكانه الصحيح.
        final ar = (_poll != null || _question != null || _slider != null) &&
                _images.isNotEmpty
            ? await _aspectOf(_images.first.bytes)
            : null;
        while (_images.isNotEmpty) {
          final first = !_extrasSent;
          final m = await _mediaToPublish(0);
          await PostService.publishMedia(PostType.story, m.bytes,
              mime: m.mime,
              ext: m.ext,
              caption: caption,
              onProgress: (p) => onProgress((_publishedCount + p) / total),
              closeFriends: _closeFriends,
              extra: <String, dynamic>{
                if (first && _poll != null) 'poll': _poll!.withAspect(ar).toMap(),
                if (first && _question != null)
                  'question': _question!.withAspect(ar).toMap(),
                if (first && _slider != null)
                  'slider': _slider!.withAspect(ar).toMap(),
                if (first && !_info.isEmpty) ..._info.toExtra(),
                if (first && _mentions.isNotEmpty)
                  'mentions': [for (final u in _mentions) u.toMap()],
              });
          if (first && _mentions.isNotEmpty) {
            unawaited(notifyStoryMentions(List.of(_mentions)));
          }
          _extrasSent = true;
          // نزيل المنشورة حتى لا تتكرر عند إعادة المحاولة بعد فشل جزئي.
          final done = _images.removeAt(0);
          _stickerMap.remove(done);
          _strokeMap.remove(done);
          _cur = 0;
          _publishedCount++;
        }
      } else {
        final m = _images.first;
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
              ? (_publishedCount > 1
                  ? trf('تمت إضافة {0} قصص', [_publishedCount])
                  : tr('تمت إضافة القصة'))
              : tr('تم النشر بنجاح'))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          final base = friendlyError(e, fallback: tr('فشل النشر'));
          _error = (_isStory && _publishedCount > 0)
              ? trf('{0} (نُشر {1} وبقي {2})',
                  [base, _publishedCount, _images.length])
              : base;
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
        itemBuilder: (context, i) => GestureDetector(
         onTap: (_isStory && !_busy) ? () => setState(() => _cur = i) : null,
         child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: (_isStory && i == _cur)
                        ? AppColors.brandPurple
                        : Colors.transparent,
                    width: 2.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.memory(_images[i].bytes,
                    width: 120, height: 150, fit: BoxFit.cover),
              ),
            ),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: GestureDetector(
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _stickerMap.remove(_images[i]);
                          _strokeMap.remove(_images[i]);
                          _images.removeAt(i);
                          if (_cur > i || _cur >= _images.length) {
                            _cur = (_cur - 1).clamp(0, _images.length).toInt();
                          }
                        }),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: !_dialogOpen,
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
          controller: _scroll,
          cacheExtent: 2000,
          physics: (_lockScroll || _drawing)
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: const EdgeInsets.all(16),
          children: [
            if (_images.length == 1 || (_isStory && _images.isNotEmpty))
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: _frozenImgH ??
                        MediaQuery.of(context).size.height * 0.5),
                    child: Stack(
                     children: [
                      RepaintBoundary(
                      key: _captureKey,
                      child: Stack(
                        children: [
                          Image.memory(_curImage.bytes,
                              key: ValueKey(_curImage), fit: BoxFit.contain),
                          if (widget.kind == CreateKind.post)
                            PositionedDirectional(
                              top: 6,
                              end: 6,
                              child: GestureDetector(
                                onTap: _busy
                                    ? null
                                    : () => setState(() => _images.clear()),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded,
                                      size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          if (_canSticker)
                            Positioned.fill(
                              child: StrokesLayer(
                                  key: ValueKey('strokes-${_curImage.hashCode}'),
                                  strokes: _strokesOf(_curImage)),
                            ),
                          if (_canSticker)
                            Positioned.fill(
                              child: StickerLayer(
                                  key: ValueKey(_curImage),
                                  items: _stickers,
                                  enabled: !_busy && !_drawing,
                                  onChanged: () => setState(() {}),
                                  onEditText: _editText,
                                  onTouching: (v) =>
                                      setState(() => _lockScroll = v)),
                            ),
                          if (_canSticker && _drawing)
                            Positioned.fill(
                              child: DrawingInput(
                                key: ValueKey('draw-${_curImage.hashCode}'),
                                strokes: _strokesOf(_curImage),
                                color: _penColor,
                                width: _penWidth,
                                erase: _erase,
                                onChanged: () => setState(() {}),
                              ),
                            ),
                        ],
                      ),
                    ),
                      // الاستطلاع والأسئلة والشريط فوق الصورة (لا تُدمج في الصورة).
                      if (_isStory && _canSticker)
                        Positioned.fill(
                          child: StoryCardsLayer(
                            poll: _poll,
                            question: _question,
                            slider: _slider,
                            enabled: !_busy && !_drawing,
                            onPoll: (v) => setState(() => _poll = v),
                            onQuestion: (v) => setState(() => _question = v),
                            onSlider: (v) => setState(() => _slider = v),
                            onEditPoll: _editPoll,
                            onEditQuestion: _editQuestion,
                            onEditSlider: _editSlider,
                            onTouching: (v) => setState(() => _lockScroll = v),
                          ),
                        ),
                     ],
                    ),
                  ),
                ),
              ),
            if (_canSticker && _drawing)
              DrawToolbar(
                color: _penColor,
                width: _penWidth,
                erase: _erase,
                canUndo: _strokesOf(_curImage).isNotEmpty,
                onColor: (c) => setState(() => _penColor = c),
                onWidth: (w) => setState(() => _penWidth = w),
                onErase: (v) => setState(() => _erase = v),
                onUndo: () => setState(() {
                  final l = _strokesOf(_curImage);
                  if (l.isNotEmpty) l.removeLast();
                }),
                onDone: () => setState(() => _drawing = false),
              ),
            if (widget.kind == CreateKind.story)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StoryAudienceSelector(
                    close: _closeFriends,
                    enabled: !_busy,
                    onChanged: (v) {
                      if (mounted) setState(() => _closeFriends = v);
                    }),
              ),
            if (_canSticker)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _editPhoto,
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(tr('تعديل الصورة')),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _drawing = !_drawing;
                              _erase = false;
                            }),
                    icon: const Icon(Icons.brush_rounded),
                    label: Text(tr('رسم')),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _addText,
                    icon: const Icon(Icons.text_fields_rounded),
                    label: Text(tr('نص')),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _addSticker,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    label: Text(tr('ملصق')),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _editPoll,
                    icon: const Icon(Icons.poll_outlined),
                    label: Text(tr('استطلاع')),
                  ),
                  StoryInfoMenu(info: _info, onChanged: () => setState(() {})),
                  TextButton.icon(
                    onPressed: _busy ? null : _editSlider,
                    icon: const Icon(Icons.linear_scale_rounded),
                    label: Text(tr('شريط إيموجي')),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _editQuestion,
                    icon: const Icon(Icons.help_outline_rounded),
                    label: Text(tr('أسئلة')),
                  ),
                ],
              ),
            if (_canSticker)
              MentionEditor(
                  mentions: _mentions,
                  enabled: !_busy,
                  onChanged: () {
                    if (mounted) setState(() {});
                  }),
            if (_canSticker && !_info.isEmpty)
              StoryInfoChips(
                  info: _info,
                  enabled: !_busy,
                  onChanged: () => setState(() {})),
            if (_canSticker && _slider != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  avatar: const Icon(Icons.linear_scale_rounded, size: 18),
                  label: Text(_slider!.q.isEmpty ? _slider!.e : '${_slider!.e} ${_slider!.q}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onPressed: _busy ? null : _editSlider,
                  onDeleted: _busy ? null : () => setState(() => _slider = null),
                ),
              ),
            if (_canSticker && _question != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  avatar: const Icon(Icons.help_outline_rounded, size: 18),
                  label: Text(_question!.q,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onPressed: _busy ? null : _editQuestion,
                  onDeleted:
                      _busy ? null : () => setState(() => _question = null),
                ),
              ),
            if (_canSticker && _poll != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  avatar: const Icon(Icons.poll_outlined, size: 18),
                  label: Text(_poll!.q,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onPressed: _busy ? null : _editPoll,
                  onDeleted: _busy ? null : () => setState(() => _poll = null),
                ),
              ),
            if (_canSticker && _stickers.isNotEmpty)
              Text(
                  tr('حرّك الملصق بإصبعك، وبإصبعين للتكبير، واسحبه إلى السلة لحذفه'),
                  style: TextStyle(
                      color: context.appColors.textDim, fontSize: 12.5)),
            if (_images.length > 1) ...[
              const SizedBox(height: 8),
              _albumStrip(),
            ],
            if (_images.isNotEmpty &&
                (_canAlbum || _isStory) &&
                _images.length < _maxImages)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addMore,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(trf('إضافة صور ({0}/{1})',
                      [_images.length, _maxImages])),
                ),
              ),
            const SizedBox(height: 16),
            if (_allowVideo) ...[
              _previewBox(context),
              TextField(
                controller: _videoLink,
                autofocus: _isVideoKind,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: _isVideoKind
                      ? tr('الصق رابط الفيديو أو البث')
                      : tr('رابط فيديو (اختياري)'),
                  prefixIcon: const Icon(Icons.play_circle_outline_rounded),
                  errorText: _linkError,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              decoration: _styled
                  ? BoxDecoration(
                      gradient: postBgGradient(_tbg),
                      borderRadius: BorderRadius.circular(14))
                  : null,
              child: TextField(
                controller: _caption,
                minLines: _textOnly ? 6 : 3,
                maxLines: _textOnly ? 12 : 5,
                maxLength: 500,
                textAlign: _styled ? TextAlign.center : TextAlign.start,
                style: _canStyle && (_styled || postTextColor(_tc) != null)
                    ? TextStyle(
                        color: postTextColor(_tc) ??
                            (_styled ? Colors.white : null),
                        fontSize: _styled ? 22 : null,
                        fontWeight: _styled ? FontWeight.w800 : null)
                    : null,
                decoration: InputDecoration(
                  hintText: _hint,
                  hintStyle:
                      _styled ? const TextStyle(color: Colors.white70) : null,
                  filled: _styled ? false : null,
                  counterStyle:
                      _styled ? const TextStyle(color: Colors.white70) : null,
                  border: _styled ? InputBorder.none : null,
                  enabledBorder: _styled ? InputBorder.none : null,
                  focusedBorder: _styled ? InputBorder.none : null,
                ),
              ),
            ),
            if (_canStyle)
              PostStylePicker(
                bg: _tbg,
                textColor: _tc,
                onBg: (v) => setState(() => _tbg = v),
                onTextColor: (v) => setState(() => _tc = v),
              ),
            if (widget.kind == CreateKind.post && _images.isEmpty)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _addFirstPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(tr('ملفات الجهاز')),
                  ),
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _addFirstPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(tr('التقاط صورة')),
                  ),
                ],
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
