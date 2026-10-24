import 'package:flutter/widgets.dart';

/// يثبّت مقاسات الشاشة (لوحة المفاتيح والهوامش) طالما تغطيها نافذة أو قائمة،
/// فلا تهتز الصفحة التي خلفها عند ظهور لوحة المفاتيح أو اختفائها.
class FreezeWhenCovered extends StatefulWidget {
  final Widget child;
  const FreezeWhenCovered({super.key, required this.child});

  @override
  State<FreezeWhenCovered> createState() => _FreezeWhenCoveredState();
}

class _FreezeWhenCoveredState extends State<FreezeWhenCovered> {
  MediaQueryData? _frozen;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final covered = route != null && !route.isCurrent;
    final mq = MediaQuery.of(context);
    if (covered) {
      _frozen ??= mq;
    } else {
      _frozen = null;
    }
    // الهيكل ثابت دائماً حتى لا تضيع حالة الصفحة.
    return MediaQuery(data: _frozen ?? mq, child: widget.child);
  }
}
