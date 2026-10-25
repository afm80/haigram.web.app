import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/user_service.dart';
import '../services/verification_service.dart';
import '../theme.dart';
import 'common_widgets.dart' show VerifiedBadge;

/// تعليمات الدفع التي تظهر في النموذج (اكتب هنا طريقة الدفع والمبلغ).
/// اتركها فارغة إن لم ترد عرض شيء.
const String kVerificationPaymentNote = '';

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// «طلب توثيق الحساب»: يعرض حالة طلبي، ويفتح النموذج عند السماح بطلب جديد.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _refCtrl = TextEditingController();
  final _proofCtrl = TextEditingController();
  String _category = '';
  String _plan = 'monthly';
  bool _busy = false;
  bool? _lastVerified;

  @override
  void dispose() {
    _refCtrl.dispose();
    _proofCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await VerificationService.submit(
        category: _category,
        plan: _plan,
        paymentRef: _refCtrl.text,
        proofUrl: _proofCtrl.text,
      );
      if (!mounted) return;
      _refCtrl.clear();
      _proofCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم إرسال طلبك، وهو الآن قيد المراجعة'))),
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statusCard(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      String? body}) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                if (body != null) ...[
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(color: colors.textDim)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final colors = context.appColors;
    final canSend = !_busy && _category.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kVerificationPaymentNote.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(tr(kVerificationPaymentNote)),
          ),
          const SizedBox(height: 16),
        ],
        Text(tr('فئة الحساب'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _category.isEmpty ? null : _category,
          hint: Text(tr('اختر الفئة')),
          items: [
            for (final c in VerificationCategory.all)
              DropdownMenuItem(value: c.id, child: Text(tr(c.label))),
          ],
          onChanged: _busy ? null : (v) => setState(() => _category = v ?? ''),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Text(tr('الخطة'), style: const TextStyle(fontWeight: FontWeight.w700)),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'monthly',
          groupValue: _plan,
          title: Text(tr('شهرية')),
          subtitle: Text(tr('تنتهي العلامة بعد شهر من القبول')),
          onChanged: _busy ? null : (v) => setState(() => _plan = v ?? 'monthly'),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'permanent',
          groupValue: _plan,
          title: Text(tr('دائمة')),
          onChanged: _busy ? null : (v) => setState(() => _plan = v ?? 'monthly'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _refCtrl,
          enabled: !_busy,
          maxLength: 100,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('رقم عملية الدفع أو الإيصال'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _proofCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: tr('رابط يثبت الهوية (اختياري)'),
            helperText: tr('مثل حسابك في منصة أخرى أو موقعك الرسمي'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canSend ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('إرسال الطلب')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(tr('طلب توثيق الحساب'))),
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: UserService.profileStream(uid),
          builder: (context, userSnap) {
            final me = userSnap.data;
            // عند تغيّر حالة التوثيق (قبول/سحب من الأدمن) نحدّث النسخة المخزّنة
            // لتظهر العلامة في بقية التطبيق دون إعادة فتحه.
            if (me != null && _lastVerified != me.isVerified) {
              final first = _lastVerified == null;
              _lastVerified = me.isVerified;
              if (!first) UserService.invalidate(uid);
            }
            return StreamBuilder<VerificationRequest?>(
              stream: VerificationService.myRequest(),
              builder: (context, reqSnap) {
                if (userSnap.connectionState == ConnectionState.waiting &&
                    reqSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final req = reqSnap.data;
                final verified = me?.isVerified == true;

                Widget status;
                var showForm = false;
                if (verified) {
                  final until = me!.verifiedUntil;
                  status = _statusCard(
                    context,
                    icon: Icons.verified_rounded,
                    color: VerifiedBadge.color,
                    title: tr('حسابك موثّق'),
                    body: until == null
                        ? tr('التوثيق دائم')
                        : trf('ينتهي التوثيق في {0}', [_fmtDate(until)]),
                  );
                } else if (req != null && req.isPending) {
                  status = _statusCard(
                    context,
                    icon: Icons.hourglass_top_rounded,
                    color: Colors.orange,
                    title: tr('طلبك قيد المراجعة'),
                    body: tr('سنخبرك هنا بمجرد اتخاذ القرار'),
                  );
                } else if (req != null && req.isRejected) {
                  final retry = req.canRetryAt;
                  status = _statusCard(
                    context,
                    icon: Icons.cancel_rounded,
                    color: Colors.red,
                    title: tr('تم رفض طلبك'),
                    body: retry == null
                        ? tr('يمكنك تقديم طلب جديد الآن')
                        : trf('يمكنك الطلب من جديد بعد {0}', [_fmtDate(retry)]),
                  );
                  showForm = retry == null;
                } else if (req != null) {
                  // قُبل سابقاً ولم يعد الحساب موثّقاً (انتهت الشهرية أو سُحب).
                  status = _statusCard(
                    context,
                    icon: Icons.info_outline_rounded,
                    color: Colors.grey,
                    title: tr('انتهى توثيق حسابك'),
                    body: tr('يمكنك تقديم طلب جديد'),
                  );
                  showForm = true;
                } else {
                  status = const SizedBox.shrink();
                  showForm = true;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (req != null || verified) ...[
                      status,
                      const SizedBox(height: 20),
                    ],
                    if (showForm && !verified) _form(context),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
