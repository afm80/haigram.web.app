import 'dart:async';

import 'package:flutter/material.dart';

/// يثبّت حجم الصفحة أثناء ظهور لوحة المفاتيح.
///
/// على الويب (Chrome أندرويد) تُصغّر لوحة المفاتيح مساحة الصفحة نفسها،
/// فتنكمش صورة القصة وتتحرك عناصرها مع كل إطار من حركة الكيبورد (رجفان ووميض).
/// هنا نُبقي المحتوى بآخر حجم كامل ونترك الجزء السفلي يختفي خلف الكيبورد،
/// كما يفعل إنستغرام. تعود الصفحة لحجمها الطبيعي بعد إغلاق الكيبورد.
class KeyboardStable extends StatefulWidget {
  final Widget child;
  const KeyboardStable({super.key, required this.child});

  @override
  State<KeyboardStable> createState() => _KeyboardStableState();
}

class _KeyboardStableState extends State<KeyboardStable> {
  Size? _stable; // آخر حجم كامل (بدون كيبورد)
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _scheduleResettle() {
    if (_settle != null) return;
    // إن بقي الحجم أصغر بعد انتهاء حركة الكيبورد فهو تغيير حقيقي
    // (تدوير الشاشة مثلاً): نعتمده حجماً جديداً.
    _settle = Timer(const Duration(milliseconds: 600), () {
      _settle = null;
      if (!mounted) return;
      setState(() => _stable = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final live = c.biggest;
      final covered = ModalRoute.of(context)?.isCurrent == false;
      final st = _stable;
      if (st == null || (live.width - st.width).abs() > 1) {
        _stable = live;
        return widget.child;
      }
      if (live.height >= st.height - 1) {
        // رجع الحجم كاملاً (أو كبر): نعتمده.
        _settle?.cancel();
        _settle = null;
        _stable = live;
        return widget.child;
      }
      // الصفحة أصغر من حجمها الكامل: كيبورد ظاهر أو يُغلق.
      if (!covered) _scheduleResettle();
      return OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: live.width,
        maxWidth: live.width,
        minHeight: st.height,
        maxHeight: st.height,
        child: widget.child,
      );
    });
  }
}
