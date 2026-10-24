import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import '../services/post_service.dart';
import 'sticker_sheet.dart' show StickerGlyph;

const List<String> _sliderEmojis = ['😍', '🔥', '😂', '😮', '😢', '👏', '❤️', '👍'];

/// نافذة إنشاء شريط الإيموجي: سؤال اختياري واختيار الإيموجي. تعيد null عند الإلغاء.
Future<StorySlider?> showSliderDialog(BuildContext context,
    {StorySlider? initial}) {
  return showDialog<StorySlider>(
    context: context,
    builder: (_) => _SliderDialog(initial: initial),
  );
}

class _SliderDialog extends StatefulWidget {
  final StorySlider? initial;
  const _SliderDialog({this.initial});

  @override
  State<_SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<_SliderDialog> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initial?.q ?? tr('ما رأيك؟'));
  late String _e = widget.initial?.e ?? _sliderEmojis.first;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('شريط إيموجي')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              maxLength: 100,
              decoration: InputDecoration(labelText: tr('السؤال')),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _sliderEmojis)
                  GestureDetector(
                    onTap: () => setState(() => _e = e),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: e == _e
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2),
                      ),
                      child: StickerGlyph(e, size: 32),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('إلغاء'))),
        FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(StorySlider(q: _q.text.trim(), e: _e)),
            child: Text(tr('تم'))),
      ],
    );
  }
}

/// بطاقة شريط الإيموجي فوق القصة: يسحب المشاهد الإيموجي ويرسل تقييمه عند رفع إصبعه
/// (مرة واحدة)، ثم يرى متوسط الجميع. لصاحب القصة المتوسط وعدد المقيّمين مباشرة.
class StorySliderCard extends StatefulWidget {
  final Post story;
  final StorySlider slider;
  final bool mine;
  const StorySliderCard(
      {super.key,
      required this.story,
      required this.slider,
      required this.mine});

  @override
  State<StorySliderCard> createState() => _StorySliderCardState();
}

class _StorySliderCardState extends State<StorySliderCard> {
  double _value = 0.5; // موضع الإيموجي (0..1)
  int? _my; // تقييمي بعد الإرسال (0..100)
  int _count = 0;
  double _avg = 0; // 0..100
  bool _loaded = false;
  bool _busy = false;

  bool get _showResults => widget.mine || _my != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    int? my;
    if (!widget.mine) {
      try {
        my = await PostService.mySliderVote(widget.story.id);
      } catch (_) {}
    }
    var count = 0;
    var avg = 0.0;
    if (widget.mine || my != null) {
      try {
        final r = await PostService.sliderStats(widget.story.id);
        count = r.$1;
        avg = r.$2;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _my = my;
      if (my != null) _value = my / 100;
      _count = count;
      _avg = avg;
      _loaded = true;
    });
  }

  Future<void> _submit() async {
    if (_busy || widget.mine || _my != null) return;
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    final v = (_value * 100).round();
    setState(() => _busy = true);
    try {
      await PostService.voteSlider(widget.story.id, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذر إرسال التقييم'))));
      return;
    }
    if (!mounted) return;
    setState(() {
      _my = v;
      _busy = false;
    });
    try {
      final r = await PostService.sliderStats(widget.story.id);
      if (!mounted) return;
      setState(() {
        _count = r.$1;
        _avg = r.$2;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sl = widget.slider;
    final canDrag = !widget.mine && _my == null && !_busy;
    // موضع الإيموجي: لصاحب القصة وللمقيّم بعد الإرسال يظهر المتوسط، وإلا موضع إصبعي.
    final shown = _showResults && _loaded && _count > 0 ? _avg / 100 : _value;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sl.q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(sl.q,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.3)),
            ),
          LayoutBuilder(builder: (context, c) {
            const thumb = 44.0;
            final trackW = c.maxWidth - thumb;
            double fromDx(double dx) =>
                ((dx - thumb / 2) / trackW).clamp(0.0, 1.0).toDouble();
            // الاتجاه: من اليسار لليمين دائماً (ثابت لا ينعكس مع RTL).
            return Directionality(
              textDirection: TextDirection.ltr,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: canDrag
                    ? (d) => setState(() => _value = fromDx(d.localPosition.dx))
                    : null,
                onTapUp: canDrag ? (_) => _submit() : null,
                onHorizontalDragUpdate: canDrag
                    ? (d) => setState(() => _value = fromDx(d.localPosition.dx))
                    : null,
                onHorizontalDragEnd: canDrag ? (_) => _submit() : null,
                child: SizedBox(
                  height: thumb + 8,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned(
                        left: thumb / 2,
                        right: thumb / 2,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            color: Colors.white30,
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumb / 2,
                        width: trackW * shown,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        left: trackW * shown,
                        child: StickerGlyph(sl.e, size: thumb),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (widget.mine || _my != null) ...[
            const SizedBox(height: 4),
            Text(
              _count == 0
                  ? tr('لا توجد تقييمات بعد')
                  : trf('المتوسط {0}% · {1} تقييم', [_avg.round(), _count]),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
