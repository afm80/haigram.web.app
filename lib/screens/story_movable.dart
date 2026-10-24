import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/post_service.dart';
import 'sticker_sheet.dart' show StickerGlyph;

/// مواضع افتراضية (نسبة من الارتفاع) لأول وضع لكل عنصر.
const double kPollDefY = 0.62;
const double kQuestionDefY = 0.46;
const double kSliderDefY = 0.78;

/// عرض البطاقة كنسبة من عرض الوسائط (يستخدمه المحرر والعارض معاً).
double storyCardWidth(double mediaWidth) =>
    (mediaWidth * 0.8).clamp(170.0, 360.0).toDouble();

const double _trashY = 0.86;

class _Pos {
  double x, y, s;
  _Pos(this.x, this.y, this.s);
}

/// طبقة في المحرر تضع الاستطلاع وصندوق الأسئلة وشريط الإيموجي فوق الصورة:
/// سحب للتحريك، وإصبعان للتكبير، والسحب إلى السلة للحذف، والنقر للتعديل.
/// يجب وضعها فوق الصورة (خارج الجزء الذي يُلتقط ويُدمج في الصورة).
class StoryCardsLayer extends StatefulWidget {
  final StoryPoll? poll;
  final StoryQuestion? question;
  final StorySlider? slider;
  final ValueChanged<StoryPoll?> onPoll;
  final ValueChanged<StoryQuestion?> onQuestion;
  final ValueChanged<StorySlider?> onSlider;
  final VoidCallback? onEditPoll;
  final VoidCallback? onEditQuestion;
  final VoidCallback? onEditSlider;
  final bool enabled;

  /// true عند لمس بطاقة وfalse عند رفع الإصبع (ليوقف الشاشة التمرير).
  final ValueChanged<bool>? onTouching;

  const StoryCardsLayer({
    super.key,
    required this.poll,
    required this.question,
    required this.slider,
    required this.onPoll,
    required this.onQuestion,
    required this.onSlider,
    this.onEditPoll,
    this.onEditQuestion,
    this.onEditSlider,
    this.enabled = true,
    this.onTouching,
  });

  @override
  State<StoryCardsLayer> createState() => _StoryCardsLayerState();
}

class _StoryCardsLayerState extends State<StoryCardsLayer> {
  // الموضع المحلي أثناء السحب: لا نُعيد بناء الشاشة كلها مع كل حركة،
  // ونُبلغها مرة واحدة عند رفع الإصبع.
  _Pos? _pp, _pq, _ps;
  String? _active; // 'poll' | 'question' | 'slider'
  double _base = 1;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _syncAll();
  }

  @override
  void didUpdateWidget(covariant StoryCardsLayer old) {
    super.didUpdateWidget(old);
    if (_active != null) return; // لا نقطع سحباً جارياً
    _syncAll();
  }

  void _syncAll() {
    final p = widget.poll, q = widget.question, s = widget.slider;
    _pp = p == null ? null : _Pos(p.x ?? 0.5, p.y ?? kPollDefY, p.s ?? 1);
    _pq = q == null
        ? null
        : _Pos(q.x ?? 0.5, q.y ?? kQuestionDefY, q.s ?? 1);
    _ps = s == null ? null : _Pos(s.x ?? 0.5, s.y ?? kSliderDefY, s.s ?? 1);
  }

  void _down() {
    _pointers++;
    if (_pointers == 1) widget.onTouching?.call(true);
  }

  void _up() {
    if (_pointers == 0) return;
    _pointers--;
    if (_pointers == 0) widget.onTouching?.call(false);
  }

  void _commit(String kind, bool remove) {
    switch (kind) {
      case 'poll':
        final p = _pp!;
        widget.onPoll(
            remove ? null : widget.poll?.withPos(x: p.x, y: p.y, s: p.s));
        break;
      case 'question':
        final p = _pq!;
        widget.onQuestion(
            remove ? null : widget.question?.withPos(x: p.x, y: p.y, s: p.s));
        break;
      default:
        final p = _ps!;
        widget.onSlider(
            remove ? null : widget.slider?.withPos(x: p.x, y: p.y, s: p.s));
    }
  }

  Widget _card(String kind, _Pos p, double w, double h, Widget child,
      VoidCallback? onTap) {
    final cardW = storyCardWidth(w);
    return Positioned(
      key: ValueKey(kind),
      left: p.x * w,
      top: p.y * h,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.scale(
          scale: p.s,
          child: Listener(
            onPointerDown: (_) => _down(),
            onPointerUp: (_) => _up(),
            onPointerCancel: (_) => _up(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? onTap : null,
              onScaleStart: widget.enabled
                  ? (_) {
                      _base = p.s;
                      setState(() => _active = kind);
                    }
                  : null,
              onScaleUpdate: widget.enabled
                  ? (d) => setState(() {
                        p.x = (p.x + d.focalPointDelta.dx / w)
                            .clamp(0.05, 0.95)
                            .toDouble();
                        p.y = (p.y + d.focalPointDelta.dy / h)
                            .clamp(0.04, 0.97)
                            .toDouble();
                        p.s = (_base * d.scale).clamp(0.55, 1.8).toDouble();
                      })
                  : null,
              onScaleEnd: widget.enabled
                  ? (_) {
                      final remove = p.y > _trashY;
                      setState(() => _active = null);
                      _commit(kind, remove);
                    }
                  : null,
              child: SizedBox(width: cardW, child: IgnorePointer(child: child)),
            ),
          ),
        ),
      ),
    );
  }

  _Pos? _posOf(String? kind) => kind == 'poll'
      ? _pp
      : kind == 'question'
          ? _pq
          : kind == 'slider'
              ? _ps
              : null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final act = _posOf(_active);
      final over = act != null && act.y > _trashY;
      final trashSize = over ? 56.0 : 46.0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.slider != null && _ps != null)
            _card('slider', _ps!, w, h, StorySliderPreview(widget.slider!),
                widget.onEditSlider),
          if (widget.question != null && _pq != null)
            _card('question', _pq!, w, h,
                StoryQuestionPreview(widget.question!), widget.onEditQuestion),
          if (widget.poll != null && _pp != null)
            _card('poll', _pp!, w, h, StoryPollPreview(widget.poll!),
                widget.onEditPoll),
          if (_active != null)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: trashSize,
                  height: trashSize,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: over ? Colors.red : Colors.black54),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ---------- معاينات ثابتة للبطاقات (بنفس شكلها في العارض) ----------

const _cardColor = Color(0xB3000000);

const _qStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.w800,
    fontSize: 17,
    height: 1.3);

class StoryPollPreview extends StatelessWidget {
  final StoryPoll poll;
  const StoryPollPreview(this.poll, {super.key});

  Widget _opt(String t) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(12)),
          child: Text(t,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _cardColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(poll.q, textAlign: TextAlign.center, style: _qStyle),
            const SizedBox(height: 10),
            Row(children: [
              _opt(poll.a),
              const SizedBox(width: 8),
              _opt(poll.b),
            ]),
          ],
        ),
      );
}

class StoryQuestionPreview extends StatelessWidget {
  final StoryQuestion question;
  const StoryQuestionPreview(this.question, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _cardColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(question.q, textAlign: TextAlign.center, style: _qStyle),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(tr('اكتب إجابتك...'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.send_rounded, color: Colors.white),
            ]),
          ],
        ),
      );
}

class StorySliderPreview extends StatelessWidget {
  final StorySlider slider;
  const StorySliderPreview(this.slider, {super.key});

  @override
  Widget build(BuildContext context) {
    const thumb = 44.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
          color: _cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slider.q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(slider.q, textAlign: TextAlign.center, style: _qStyle),
            ),
          LayoutBuilder(builder: (context, c) {
            final trackW = c.maxWidth - thumb;
            return Directionality(
              textDirection: TextDirection.ltr,
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
                            color: Colors.white30),
                      ),
                    ),
                    Positioned(
                      left: trackW * 0.5,
                      child: StickerGlyph(slider.e, size: thumb),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
