import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import '../theme.dart';
import '../video_source.dart';

/// رفع فيديو من الجهاز: اختيار الملف، وصف اختياري، ثم الرفع إلى Cloudflare R2
/// ونشره كمنشور فيديو (يُعرض بمشغّل الملف المباشر الموجود أصلاً).
class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key});

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  Uint8List? _bytes;
  String _name = '';
  String _mime = '';
  bool _busy = false;
  String? _error;

  static const _mimes = {
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final f = await _picker.pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      final name = f.name;
      final dot = name.lastIndexOf('.');
      final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
      final mime = _mimes[ext];
      if (mime == null) {
        setState(() => _error = tr('صيغة الفيديو غير مدعومة (mp4 أو mov أو webm)'));
        return;
      }
      final bytes = await f.readAsBytes();
      if (bytes.length > PostService.maxVideoBytes) {
        setState(() => _error = tr('الفيديو كبير جداً (الحد 100 ميغابايت)'));
        return;
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _name = name;
        _mime = mime;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e, fallback: tr('تعذر اختيار الفيديو')));
      }
    }
  }

  Future<void> _publish() async {
    final bytes = _bytes;
    if (bytes == null) {
      setState(() => _error = tr('اختر فيديو أولاً'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await PostService.uploadVideo(bytes, _mime);
      final video = VideoSource.parse(url);
      if (video == null) throw StateError(tr('فشل رفع الفيديو، حاول مرة أخرى'));
      await PostService.publishText(_caption.text.trim(), video: video);
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(tr('تم النشر بنجاح'))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, fallback: tr('فشل النشر'));
        });
      }
    }
  }

  String _size(int b) => b >= 1024 * 1024
      ? '${(b / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: Text(tr('رفع فيديو'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy ? null : _pick,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.textDim.withOpacity(0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _bytes == null
                            ? Icons.video_library_outlined
                            : Icons.check_circle_outline_rounded,
                        size: 40,
                        color: colors.text),
                    const SizedBox(height: 10),
                    Text(
                      _bytes == null
                          ? tr('اختر فيديو من جهازك')
                          : '$_name  •  ${_size(_bytes!.length)}',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w600),
                    ),
                    if (_bytes == null) ...[
                      const SizedBox(height: 4),
                      Text(tr('mp4 أو mov أو webm حتى 100 ميغابايت'),
                          style: TextStyle(color: colors.textDim, fontSize: 12.5)),
                    ] else
                      TextButton(
                          onPressed: _busy ? null : _pick,
                          child: Text(tr('تغيير الفيديو'))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration:
                  InputDecoration(hintText: tr('أضف وصفاً للفيديو (اختياري)')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: TextStyle(color: colors.text)),
              ),
            if (_busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 4),
              Text(tr('جارٍ الرفع...'), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _publish,
              child: Text(tr('مشاركة')),
            ),
          ],
        ),
      ),
    );
  }
}
