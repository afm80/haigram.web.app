import 'package:flutter/material.dart';

/// يفتح نافذة (استطلاع / أسئلة / شريط إيموجي) بدون اهتزاز الشاشة.
///
/// سبب الاهتزاز: كان الكيبورد يُغلق من حقل الصفحة ثم يُفتح من حقل النافذة
/// والصفحة الخلفية تُعيد حساب حجمها مع كل تغيّر، وعند الإغلاق يعود التركيز
/// للحقل القديم فيُفتح الكيبورد من جديد. الحل:
///  1) نُزيل التركيز قبل فتح النافذة،
///  2) نُجمّد حجم الصفحة الخلفية (عبر [onOpen]) طوال مدة النافذة،
///  3) نُزيل التركيز بعد الإغلاق كي لا يُعاد فتح الكيبورد،
///  4) نُعيد الصفحة لوضعها بعد انتهاء حركة الكيبورد.
Future<T?> showStoryDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  ValueChanged<bool>? onOpen,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  onOpen?.call(true);
  // نترك الكيبورد القديم يُغلق قبل أن تفتح النافذة كيبوردها.
  await Future<void>.delayed(const Duration(milliseconds: 120));
  if (!context.mounted) {
    onOpen?.call(false);
    return null;
  }
  try {
    return await showDialog<T>(
      context: context,
      builder: builder,
    );
  } finally {
    FocusManager.instance.primaryFocus?.unfocus();
    // ننتظر انتهاء حركة إغلاق الكيبورد ثم نفكّ تجميد الصفحة.
    Future<void>.delayed(
        const Duration(milliseconds: 350), () => onOpen?.call(false));
  }
}
