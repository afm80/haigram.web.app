import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n.dart';
import 'user_service.dart';

/// فئات التوثيق. المعرّف (الإنجليزي) هو ما يُخزَّن، والنص للعرض فقط.
/// الفئة تظهر للأدمن في لوحة التحكم فقط ولا تُعرض للمستخدمين.
class VerificationCategory {
  final String id;
  final String label;
  const VerificationCategory(this.id, this.label);

  static const all = <VerificationCategory>[
    VerificationCategory('creator', 'صانع محتوى'),
    VerificationCategory('business', 'نشاط تجاري'),
    VerificationCategory('public_figure', 'شخصية عامة'),
    VerificationCategory('media', 'إعلامي'),
    VerificationCategory('organization', 'مؤسسة'),
    VerificationCategory('other', 'أخرى'),
  ];

  static String labelOf(String id) => tr(all
      .firstWhere((c) => c.id == id, orElse: () => const VerificationCategory('other', 'أخرى'))
      .label);
}

/// طلب توثيق المستخدم الحالي (مستند واحد بمعرّف = uid، فيستحيل وجود طلبين).
class VerificationRequest {
  /// pending | approved | rejected
  final String status;
  final String category;

  /// monthly | permanent
  final String plan;
  final String paymentRef;
  final String proofUrl;
  final DateTime? createdAt;
  final DateTime? rejectedAt;

  const VerificationRequest({
    required this.status,
    required this.category,
    required this.plan,
    required this.paymentRef,
    this.proofUrl = '',
    this.createdAt,
    this.rejectedAt,
  });

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  /// بعد الرفض: لا يمكن الطلب من جديد قبل هذا الموعد (null = يمكن الآن).
  DateTime? get canRetryAt {
    if (!isRejected) return null;
    final at = rejectedAt;
    if (at == null) return null;
    final next = at.add(const Duration(days: VerificationService.cooldownDays));
    return next.isAfter(DateTime.now()) ? next : null;
  }

  factory VerificationRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return VerificationRequest(
      status: (m['status'] ?? 'pending') as String,
      category: (m['category'] ?? 'other') as String,
      plan: (m['plan'] ?? 'monthly') as String,
      paymentRef: (m['paymentRef'] ?? '') as String,
      proofUrl: (m['proofUrl'] ?? '') as String,
      createdAt: ts(m['createdAt']),
      rejectedAt: ts(m['rejectedAt']),
    );
  }
}

class VerificationService {
  static final _db = FirebaseFirestore.instance;

  /// مدة الانتظار بعد الرفض قبل السماح بطلب جديد (تُفرض أيضاً في firestore.rules).
  static const cooldownDays = 30;

  static DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('verificationRequests').doc(uid);

  /// طلبي الحالي (null إن لم أقدّم طلباً قط).
  static Stream<VerificationRequest?> myRequest() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _ref(uid)
        .snapshots()
        .map((s) => s.exists ? VerificationRequest.fromDoc(s) : null);
  }

  /// يرسل طلباً جديداً أو يعيد تقديمه بعد الرفض/انتهاء التوثيق.
  /// يرمي [FormatException] برسالة عربية عند خطأ في المدخلات.
  static Future<void> submit({
    required String category,
    required String plan,
    required String paymentRef,
    String proofUrl = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = paymentRef.trim();
    if (ref.length < 3) {
      throw FormatException(tr('أدخل رقم عملية الدفع أو رقم الإيصال'));
    }
    if (ref.length > 100) {
      throw FormatException(tr('رقم العملية طويل جداً'));
    }
    if (!VerificationCategory.all.any((c) => c.id == category)) {
      throw FormatException(tr('اختر فئة الحساب'));
    }
    if (plan != 'monthly' && plan != 'permanent') {
      throw FormatException(tr('اختر الخطة'));
    }
    final proof = UserService.normalizeWebsite(proofUrl);
    if (proof == null || proof.length > 300) {
      throw FormatException(tr('رابط إثبات الهوية غير صالح'));
    }
    // set كاملاً (بدون merge): يُنشئ الطلب أو يستبدل طلباً مرفوضاً/منتهياً
    // ويمسح حقول القرار القديمة. القواعد تتحقق من كل حقل.
    await _ref(uid).set({
      'uid': uid,
      'category': category,
      'plan': plan,
      'paymentRef': ref,
      if (proof.isNotEmpty) 'proofUrl': proof,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
