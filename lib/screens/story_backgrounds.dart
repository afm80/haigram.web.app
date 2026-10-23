import 'package:flutter/material.dart';

/// خلفيات القصة النصية: تدرجات لونية على طريقة إنستغرام.
/// يُحفظ رقم الخلفية فقط مع القصة، فلا تغيّر ترتيب هذه القائمة بعد النشر.
const List<List<Color>> _storyBgColors = [
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
];

/// عدد الخلفيات المتاحة.
int get storyBgCount => _storyBgColors.length;

/// التدرج اللوني للرقم [index]؛ أي رقم غير صالح يعطي الخلفية الأولى.
LinearGradient storyGradient(int? index) {
  var i = index ?? 0;
  if (i < 0 || i >= _storyBgColors.length) i = 0;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _storyBgColors[i],
  );
}
