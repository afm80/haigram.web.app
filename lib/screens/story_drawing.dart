import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// خط مرسوم بالقلم فوق صورة القصة. النقاط وسماكة الخط نسبية (0 إلى 1)
/// من عرض الصورة وارتفاعها، فيبقى الرسم في مكانه مهما تغيّر حجم المعاينة.
class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width; // كنسبة من عرض الصورة
  final bool erase;
  DrawStroke(this.points, this.color, this.width, {this.erase = false});
}

/// يرسم الخطوط. الممحاة تمسح الرسم فقط (لا الصورة) عبر طبقة مستقلة.
class StrokesPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final int revision; // يتغيّر مع كل تعديل لإعادة الرسم
  StrokesPainter(this.strokes, this.revision);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width * size.width
        ..isAntiAlias = true;
      if (s.erase) paint.blendMode = BlendMode.clear;
      Offset p(Offset o) => Offset(o.dx * size.width, o.dy * size.height);
      if (s.points.length == 1) {
        canvas.drawCircle(
            p(s.points.first),
            s.width * size.width / 2,
            paint
              ..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(p(s.points.first).dx, p(s.points.first).dy);
      for (var i = 1; i < s.points.length - 1; i++) {
        final a = p(s.points[i]);
        final b = p(s.points[i + 1]);
        path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      final last = p(s.points.last);
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StrokesPainter old) =>
      old.revision != revision || old.strokes != strokes;
}

/// طبقة الرسم الظاهرة دائماً فوق الصورة (للعرض فقط، لا تستقبل اللمس).
class StrokesLayer extends StatelessWidget {
  final List<DrawStroke> strokes;
  const StrokesLayer({super.key, required this.strokes});

  @override
  Widget build(BuildContext context) {
    final rev = strokes.fold<int>(strokes.length, (a, s) => a + s.points.length);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: StrokesPainter(strokes, rev),
      ),
    );
  }
}

/// طبقة اللمس أثناء الرسم: تلتقط حركة الإصبع وتضيف الخطوط إلى [strokes].
/// يجب وضعها داخل Positioned.fill فوق الصورة وملصقاتها.
class DrawingInput extends StatefulWidget {
  final List<DrawStroke> strokes;
  final Color color;
  final double width;
  final bool erase;
  final VoidCallback onChanged;
  const DrawingInput({
    super.key,
    required this.strokes,
    required this.color,
    required this.width,
    required this.erase,
    required this.onChanged,
  });

  @override
  State<DrawingInput> createState() => _DrawingInputState();
}

class _DrawingInputState extends State<DrawingInput> {
  DrawStroke? _current; // يبقى عبر إعادة البناء أثناء الرسم

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      Offset norm(Offset o) => Offset(
          (o.dx / c.maxWidth).clamp(0.0, 1.0).toDouble(),
          (o.dy / c.maxHeight).clamp(0.0, 1.0).toDouble());
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final s = DrawStroke([norm(e.localPosition)], widget.color,
              widget.width,
              erase: widget.erase);
          _current = s;
          widget.strokes.add(s);
          widget.onChanged();
        },
        onPointerMove: (e) {
          _current?.points.add(norm(e.localPosition));
          widget.onChanged();
        },
        onPointerUp: (_) => _current = null,
        onPointerCancel: (_) => _current = null,
        child: const SizedBox.expand(),
      );
    });
  }
}

const List<Color> kPenColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFD60A),
  Color(0xFF34C759),
  Color(0xFF0A84FF),
  Color(0xFFBF5AF2),
  Color(0xFFFF2D87),
];

/// شريط أدوات الرسم: ألوان، سماكة، ممحاة، تراجع، وإنهاء.
class DrawToolbar extends StatelessWidget {
  final Color color;
  final double width;
  final bool erase;
  final bool canUndo;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;
  final ValueChanged<bool> onErase;
  final VoidCallback onUndo;
  final VoidCallback onDone;
  const DrawToolbar({
    super.key,
    required this.color,
    required this.width,
    required this.erase,
    required this.canUndo,
    required this.onColor,
    required this.onWidth,
    required this.onErase,
    required this.onUndo,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
          color: colors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in kPenColors)
                  GestureDetector(
                    onTap: () {
                      onColor(c);
                      onErase(false);
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 4),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (!erase && c == color)
                                ? AppColors.brandPurple
                                : Colors.grey,
                            width: (!erase && c == color) ? 3 : 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: tr('ممحاة'),
                onPressed: () => onErase(!erase),
                icon: Icon(Icons.auto_fix_normal_rounded,
                    color: erase ? AppColors.brandPurple : colors.textDim),
              ),
              Expanded(
                child: Slider(
                  value: width,
                  min: 0.006,
                  max: 0.05,
                  onChanged: onWidth,
                ),
              ),
              IconButton(
                tooltip: tr('تراجع'),
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo_rounded),
              ),
              TextButton(
                onPressed: onDone,
                child: Text(tr('تم'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
