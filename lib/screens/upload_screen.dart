import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/post_service.dart';
import '../theme.dart';
import '../web_trim.dart';

enum UploadKind { video, photo, text }

/// حدود الرفع للحفاظ على مجانية الخدمة.
const maxVideoSeconds = 60;
const maxSourceBytes = 300 * 1024 * 1024; // أقصى حجم أصلي يمكن قصّه داخل المتصفح
// في وضع التجربة (Firestore) الحدود أصغر حفاظاً على الحصة المجانية.
int get maxVideoBytes => PostService.useStorage ? 40 * 1024 * 1024 : 15 * 1024 * 1024;
int get maxPhotoBytes => PostService.useStorage ? 5 * 1024 * 1024 : 3 * 1024 * 1024;

class UploadScreen extends StatefulWidget {
  final UploadKind kind;
  const UploadScreen({super.key, required this.kind});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _bytes;
  String _ext = 'mp4';
  String? _fileName;
  double _progress = 0;
  bool _busy = false;
  bool _trimming = false;
  bool _wasTrimmed = false;
  String? _error;

  String get _title => switch (widget.kind) {
        UploadKind.video => 'فيديو جديد',
        UploadKind.photo => 'ألبوم صور',
        UploadKind.text => 'منشور نصي',
      };

  Future<void> _pick() async {
    setState(() => _error = null);
    if (widget.kind == UploadKind.video) {
      final f = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: maxVideoSeconds));
      if (f == null) return;
      final dot = f.name.lastIndexOf('.');
      var ext = dot > 0 ? f.name.substring(dot + 1).toLowerCase() : 'mp4';
      final secs = await _videoSeconds(f);
      if (secs == null) {
        setState(() => _error = 'تعذر قراءة الفيديو. جرّب صيغة MP4.');
        return;
      }
      if (await f.length() > maxSourceBytes) {
        setState(() => _error = 'الملف كبير جداً للمعالجة داخل المتصفح (الحد ${maxSourceBytes ~/ (1024 * 1024)}MB).');
        return;
      }

      Uint8List bytes;
      var trimmed = false;
      if (secs > maxVideoSeconds) {
        // الفيديو أطول من دقيقة: نقصّه تلقائياً إلى أول 60 ثانية.
        setState(() {
          _trimming = true;
          _fileName = f.name;
        });
        try {
          bytes = await trimVideo(f.path, ext, maxVideoSeconds);
          ext = 'mp4';
          trimmed = true;
        } catch (e) {
          setState(() {
            _trimming = false;
            _error = 'تعذر قص الفيديو تلقائياً: $e';
          });
          return;
        }
        setState(() => _trimming = false);
      } else {
        bytes = await f.readAsBytes();
      }

      if (bytes.length > maxVideoBytes) {
        setState(() => _error = 'حجم الفيديو بعد المعالجة ${(bytes.length / (1024 * 1024)).toStringAsFixed(0)}MB والحد ${maxVideoBytes ~/ (1024 * 1024)}MB. صوّره بجودة أقل (مثل 720p).');
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = f.name;
        _wasTrimmed = trimmed;
        _ext = ext == 'mov' ? 'quicktime' : ext;
      });
    } else {
      // الصور تُضغط داخل المتصفح (تصغير الأبعاد + جودة 75%) قبل الرفع.
      final f = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, maxHeight: 1080, imageQuality: 60);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > maxPhotoBytes) {
        setState(() => _error = 'الصورة كبيرة جداً');
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = f.name;
      });
    }
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

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (widget.kind != UploadKind.text && _bytes == null) {
      setState(() => _error = 'اختر ملفاً أولاً');
      return;
    }
    if (widget.kind == UploadKind.text && caption.isEmpty) {
      setState(() => _error = 'اكتب شيئاً أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      void onProgress(double p) => setState(() => _progress = p);
      switch (widget.kind) {
        case UploadKind.video:
          await PostService.publishVideo(_bytes!, _ext, caption, onProgress);
        case UploadKind.photo:
          await PostService.publishPhoto(_bytes!, caption, onProgress);
        case UploadKind.text:
          await PostService.publishText(caption);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النشر بنجاح')));
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'فشل النشر: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isText = widget.kind == UploadKind.text;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isText)
              GestureDetector(
                onTap: (_busy || _trimming) ? null : _pick,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.accent.withOpacity(0.6), width: 1.5),
                  ),
                  child: Center(
                    child: _trimming
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('الفيديو أطول من دقيقة، جارٍ قصّه تلقائياً...'),
                              Text('قد يستغرق ذلك لحظات', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                            ],
                          )
                        : _bytes == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.kind == UploadKind.video ? Icons.video_library_rounded : Icons.add_photo_alternate_rounded, size: 44, color: AppColors.accent),
                              const SizedBox(height: 8),
                              Text(widget.kind == UploadKind.video ? 'اختر فيديو (حتى دقيقة)' : 'اختر صورة'),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 44, color: Colors.greenAccent),
                              const SizedBox(height: 8),
                              Text(_fileName ?? 'تم الاختيار'),
                              Text('${(_bytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB', style: const TextStyle(color: AppColors.textDim)),
                              if (_wasTrimmed)
                                const Text('تم قصّ الفيديو إلى أول 60 ثانية', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                            ],
                          ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              minLines: isText ? 6 : 3,
              maxLines: isText ? 12 : 5,
              maxLength: 500,
              decoration: InputDecoration(hintText: isText ? 'بماذا تفكر؟ أضف #هاشتاق' : 'اكتب وصفاً مع #هاشتاقات'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: const TextStyle(color: AppColors.accent2))),
            if (_busy && !isText) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 4),
              Text('${(_progress * 100).toStringAsFixed(0)}%', textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _publish, child: const Text('نشر')),
          ],
        ),
      ),
    );
  }
}
