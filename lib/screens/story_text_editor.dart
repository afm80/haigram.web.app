import 'package:flutter/material.dart';

import '../l10n.dart';
import 'story_stickers.dart';

/// ألوان النص على صورة القصة.
const List<Color> storyTextColors = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFFFD54F),
  Color(0xFFFF5252),
  Color(0xFFFF80AB),
  Color(0xFFB388FF),
  Color(0xFF40C4FF),
  Color(0xFF69F0AE),
  Color(0xFFFF9800),
  Color(0xFF8D6E63),
];

/// عدد أنماط النص: 0 عادي بظل، 1 داخل مربع ملوّن، 2 بإطار.
const int storyTextStyleCount = 3;

/// نص القصة كما يُرسم فوق الصورة (وفي المحرر).
Widget storyTextWidget(String text, Color color, int style, double fontSize) {
  final base = TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    height: 1.25,
  );
  switch (style) {
    case 1:
      final dark = color.computeLuminance() > 0.6;
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.55, vertical: fontSize * 0.3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(fontSize * 0.4),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: base.copyWith(color: dark ? Colors.black : Colors.white)),
      );
    case 2:
      return Stack(
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = fontSize * 0.18
                  ..strokeJoin = StrokeJoin.round
                  ..color = color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
              )),
          Text(text,
              textAlign: TextAlign.center, style: base.copyWith(color: color)),
        ],
      );
    default:
      return Text(text,
          textAlign: TextAlign.center,
          style: base.copyWith(color: color, shadows: const [
            Shadow(blurRadius: 6, color: Colors.black87),
          ]));
  }
}

/// نتيجة محرر النص.
class StoryTextResult {
  final String text;
  final Color color;
  final int style;
  const StoryTextResult(this.text, this.color, this.style);
}

/// شاشة كتابة نص فوق الصورة: اكتب، اختر اللون والنمط، ثم «تم».
/// تعيد null عند الإلغاء. نص فارغ عند التعديل يعني حذف النص.
Future<StoryTextResult?> showStoryTextEditor(BuildContext context,
    {StoryStickerItem? initial}) {
  return Navigator.of(context, rootNavigator: true).push<StoryTextResult>(
    PageRouteBuilder<StoryTextResult>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _StoryTextEditor(initial: initial),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class _StoryTextEditor extends StatefulWidget {
  final StoryStickerItem? initial;
  const _StoryTextEditor({this.initial});

  @override
  State<_StoryTextEditor> createState() => _StoryTextEditorState();
}

class _StoryTextEditorState extends State<_StoryTextEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial?.text ?? '');
  late Color _color = widget.initial?.color ?? Colors.white;
  late int _style = widget.initial?.style ?? 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.pop(context, StoryTextResult(_text.text.trim(), _color, _style));
  }

  TextStyle get _fieldStyle {
    final dark = _color.computeLuminance() > 0.6;
    return TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: _style == 1 ? (dark ? Colors.black : Colors.white) : _color,
      shadows: _style == 0
          ? const [Shadow(blurRadius: 6, color: Colors.black87)]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('إلغاء'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('نمط النص'),
                    onPressed: () => setState(
                        () => _style = (_style + 1) % storyTextStyleCount),
                    icon: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _style == 1 ? Colors.white : Colors.transparent,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text('A',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _style == 1 ? Colors.black : Colors.white)),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _done,
                    child: Text(tr('تم'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: _style == 1
                        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                        : EdgeInsets.zero,
                    decoration: _style == 1
                        ? BoxDecoration(
                            color: _color,
                            borderRadius: BorderRadius.circular(14))
                        : null,
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      maxLength: 100,
                      minLines: 1,
                      maxLines: 6,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.multiline,
                      cursorColor: Colors.white,
                      style: _fieldStyle,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        hintText: tr('اكتب نصاً...'),
                        hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontSize: 28,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: storyTextColors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = storyTextColors[i];
                  final selected = c == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: selected ? 38 : 32,
                      height: selected ? 38 : 32,
                      margin: EdgeInsets.symmetric(vertical: selected ? 7 : 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c,
                        border: Border.all(
                            color: Colors.white, width: selected ? 3 : 1.5),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
