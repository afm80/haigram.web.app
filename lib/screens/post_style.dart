import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/post_service.dart';
import '../theme.dart';

/// خلفيات المنشور النصي (على طريقة فيسبوك). يُحفظ رقم الخلفية فقط مع المنشور
/// (الحقل tbg)، فلا تغيّر ترتيب هذه القائمة بعد النشر.
const List<List<Color>> _postBgColors = [
  [Color(0xFF833AB4), Color(0xFFFD1D1D)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFF2193B0), Color(0xFF6DD5ED)],
  [Color(0xFFFF512F), Color(0xFFF09819)],
  [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  [Color(0xFFEE0979), Color(0xFFFF6A00)],
  [Color(0xFF232526), Color(0xFF414345)],
  [Color(0xFF0F2027), Color(0xFF2C5364)],
  [Color(0xFFDA22FF), Color(0xFF9733EE)],
  [Color(0xFFCB2D3E), Color(0xFFEF473A)],
  [Color(0xFF1D976C), Color(0xFF93F9B9)],
  [Color(0xFF0575E6), Color(0xFF021B79)],
];

/// ألوان النص (الحقل tc). يُحفظ الرقم فقط.
const List<Color> _postTextColors = [
  Color(0xFFFFFFFF),
  Color(0xFF111111),
  Color(0xFFFFD54F),
  Color(0xFFFF5252),
  Color(0xFF69F0AE),
  Color(0xFF40C4FF),
  Color(0xFFFF80AB),
  Color(0xFFB388FF),
];

int get postBgCount => _postBgColors.length;
int get postTextColorCount => _postTextColors.length;

bool _validBg(int? i) => i != null && i >= 0 && i < _postBgColors.length;
bool _validTc(int? i) => i != null && i >= 0 && i < _postTextColors.length;

/// تدرج الخلفية للرقم [i]، أو null إن لم تكن هناك خلفية صالحة.
LinearGradient? postBgGradient(int? i) => _validBg(i)
    ? LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _postBgColors[i!],
      )
    : null;

/// لون النص للرقم [i]، أو null (= اللون الافتراضي).
Color? postTextColor(int? i) => _validTc(i) ? _postTextColors[i!] : null;

/// خلفية مربع المنشور النصي في شبكة الملف الشخصي: خلفيته إن اختارها صاحبه،
/// وإلا لون ثابت يُشتق من رقم المنشور (يبقى نفسه في كل مرة).
LinearGradient postGridGradient(Post p) {
  final own = postBgGradient(p.tbg);
  if (own != null) return own;
  final h = p.id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return postBgGradient(h % _postBgColors.length)!;
}

/// لون نص مربع الشبكة: لون المنشور إن كانت له خلفية، وإلا الأبيض.
Color postGridTextColor(Post p) =>
    _validBg(p.tbg) ? (postTextColor(p.tc) ?? Colors.white) : Colors.white;

/// صفان من الدوائر الملونة: خلفية المنشور، ثم لون النص.
class PostStylePicker extends StatelessWidget {
  final int? bg;
  final int? textColor;
  final ValueChanged<int?> onBg;
  final ValueChanged<int?> onTextColor;
  const PostStylePicker({
    super.key,
    required this.bg,
    required this.textColor,
    required this.onBg,
    required this.onTextColor,
  });

  Widget _dot({
    required bool selected,
    required VoidCallback onTap,
    Color? color,
    Gradient? gradient,
    Widget? child,
  }) {
    return Builder(builder: (context) {
      final colors = context.appColors;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsetsDirectional.only(end: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            gradient: gradient,
            border: Border.all(
              color: selected ? colors.text : colors.text.withOpacity(0.2),
              width: selected ? 3 : 1,
            ),
          ),
          child: child,
        ),
      );
    });
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.appColors.textDim)),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, tr('خلفية المنشور')),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _dot(
                selected: bg == null,
                onTap: () => onBg(null),
                color: colors.surfaceHigh,
                child: Icon(Icons.block_rounded,
                    size: 18, color: colors.textDim),
              ),
              for (var i = 0; i < _postBgColors.length; i++)
                _dot(
                  selected: bg == i,
                  onTap: () => onBg(i),
                  gradient: postBgGradient(i),
                ),
            ],
          ),
        ),
        _label(context, tr('لون النص')),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _dot(
                selected: textColor == null,
                onTap: () => onTextColor(null),
                color: colors.surfaceHigh,
                child: Text('A',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: colors.text)),
              ),
              for (var i = 0; i < _postTextColors.length; i++)
                _dot(
                  selected: textColor == i,
                  onTap: () => onTextColor(i),
                  color: _postTextColors[i],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
