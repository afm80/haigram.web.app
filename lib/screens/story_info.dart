import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../services/post_service.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String _timeText(DateTime t, int mode) {
  final clock = '${_two(t.hour)}:${_two(t.minute)}';
  final date = '${t.year}/${_two(t.month)}/${_two(t.day)}';
  return mode == 0 ? clock : (mode == 1 ? date : '$date  $clock');
}

/// يضمن أن الرابط يبدأ بـ https:// أو http:// ويعيده منظّفاً، أو null إن لم يصلح.
String? normalizeStoryUrl(String raw) {
  var t = raw.trim();
  if (t.isEmpty || t.contains(' ') || t.length > 300) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) {
    t = 'https://$t';
  }
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
  return t;
}

// ---------------------------- نوافذ الإنشاء ----------------------------

Future<void> showLinkDialog(BuildContext context, StoryInfo info,
    VoidCallback onChanged) async {
  final url = TextEditingController(text: info.linkUrl ?? '');
  final label = TextEditingController(text: info.linkLabel ?? '');
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(tr('رابط')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('الرابط')),
            ),
            TextField(
              controller: label,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('النص الظاهر (اختياري)')),
            ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6), child: Text(error!)),
          ],
        ),
        actions: [
          if (info.linkUrl != null)
            TextButton(
                onPressed: () {
                  info.linkUrl = null;
                  info.linkLabel = null;
                  onChanged();
                  Navigator.pop(ctx);
                },
                child: Text(tr('إزالة'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () {
              final u = normalizeStoryUrl(url.text);
              if (u == null) {
                setS(() => error = tr('رابط غير صالح'));
                return;
              }
              info.linkUrl = u;
              info.linkLabel = label.text.trim();
              onChanged();
              Navigator.pop(ctx);
            },
            child: Text(tr('تم')),
          ),
        ],
      ),
    ),
  );
  url.dispose();
  label.dispose();
}

Future<void> showLocationDialog(BuildContext context, StoryInfo info,
    VoidCallback onChanged) async {
  final name = TextEditingController(text: info.location ?? '');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('موقع')),
      content: TextField(
        controller: name,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: tr('اسم المكان')),
      ),
      actions: [
        if (info.location != null)
          TextButton(
              onPressed: () {
                info.location = null;
                onChanged();
                Navigator.pop(ctx);
              },
              child: Text(tr('إزالة'))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء'))),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            if (n.isEmpty) return;
            info.location = n;
            onChanged();
            Navigator.pop(ctx);
          },
          child: Text(tr('تم')),
        ),
      ],
    ),
  );
  name.dispose();
}

Future<void> showCountdownDialog(BuildContext context, StoryInfo info,
    VoidCallback onChanged) async {
  final title = TextEditingController(text: info.countdownTitle ?? '');
  DateTime? end = info.countdownAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(info.countdownAt!);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(tr('عدّ تنازلي')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(labelText: tr('اسم الحدث')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(end == null
                  ? tr('اختر التاريخ والوقت')
                  : _timeText(end!, 2)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: end ?? now.add(const Duration(days: 1)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365 * 2)),
                );
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay.fromDateTime(end ?? now),
                );
                if (t == null) return;
                setS(() {
                  end = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  error = null;
                });
              },
            ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6), child: Text(error!)),
          ],
        ),
        actions: [
          if (info.countdownAt != null)
            TextButton(
                onPressed: () {
                  info.countdownAt = null;
                  info.countdownTitle = null;
                  onChanged();
                  Navigator.pop(ctx);
                },
                child: Text(tr('إزالة'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () {
              final t = title.text.trim();
              if (t.isEmpty || end == null) {
                setS(() => error = tr('اكتب اسم الحدث واختر الوقت'));
                return;
              }
              if (!end!.isAfter(DateTime.now())) {
                setS(() => error = tr('اختر وقتاً في المستقبل'));
                return;
              }
              info.countdownTitle = t;
              info.countdownAt = end!.millisecondsSinceEpoch;
              onChanged();
              Navigator.pop(ctx);
            },
            child: Text(tr('تم')),
          ),
        ],
      ),
    ),
  );
  title.dispose();
}

Future<void> showTimeDialog(BuildContext context, StoryInfo info,
    VoidCallback onChanged) async {
  final labels = [tr('الساعة'), tr('التاريخ'), tr('التاريخ والساعة')];
  await showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('ملصق الوقت')),
      children: [
        for (var i = 0; i < labels.length; i++)
          SimpleDialogOption(
            onPressed: () {
              info.timeMode = i;
              onChanged();
              Navigator.pop(ctx);
            },
            child: Text(labels[i]),
          ),
        if (info.timeMode != null)
          SimpleDialogOption(
            onPressed: () {
              info.timeMode = null;
              onChanged();
              Navigator.pop(ctx);
            },
            child: Text(tr('إزالة')),
          ),
      ],
    ),
  );
}

/// قائمة منسدلة بأزرار الملصقات المعلوماتية الأربعة (للشاشات الضيقة).
class StoryInfoMenu extends StatelessWidget {
  final StoryInfo info;
  final VoidCallback onChanged;
  final Color? color;
  const StoryInfoMenu(
      {super.key, required this.info, required this.onChanged, this.color});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('ملصقات'),
      icon: Icon(Icons.sticky_note_2_outlined, color: color, size: 26),
      onSelected: (v) {
        switch (v) {
          case 'link':
            showLinkDialog(context, info, onChanged);
          case 'loc':
            showLocationDialog(context, info, onChanged);
          case 'cd':
            showCountdownDialog(context, info, onChanged);
          case 'time':
            showTimeDialog(context, info, onChanged);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'link', child: Text(tr('رابط'))),
        PopupMenuItem(value: 'loc', child: Text(tr('موقع'))),
        PopupMenuItem(value: 'cd', child: Text(tr('عدّ تنازلي'))),
        PopupMenuItem(value: 'time', child: Text(tr('الوقت'))),
      ],
    );
  }
}

/// شرائح المعلومات المضافة (للمعاينة قبل النشر) مع إمكانية الحذف والتعديل.
class StoryInfoChips extends StatelessWidget {
  final StoryInfo info;
  final VoidCallback onChanged;
  final bool enabled;
  const StoryInfoChips(
      {super.key,
      required this.info,
      required this.onChanged,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text, VoidCallback edit, VoidCallback del) =>
        InputChip(
          avatar: Icon(icon, size: 18),
          label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          onPressed: enabled ? edit : null,
          onDeleted: enabled
              ? () {
                  del();
                  onChanged();
                }
              : null,
        );
    return Wrap(
      spacing: 8,
      children: [
        if (info.linkUrl != null)
          chip(
              Icons.link_rounded,
              (info.linkLabel ?? '').isEmpty ? info.linkUrl! : info.linkLabel!,
              () => showLinkDialog(context, info, onChanged),
              () {
                info.linkUrl = null;
                info.linkLabel = null;
              }),
        if (info.location != null)
          chip(Icons.place_outlined, info.location!,
              () => showLocationDialog(context, info, onChanged),
              () => info.location = null),
        if (info.countdownAt != null)
          chip(Icons.timer_outlined, info.countdownTitle ?? '',
              () => showCountdownDialog(context, info, onChanged), () {
            info.countdownAt = null;
            info.countdownTitle = null;
          }),
        if (info.timeMode != null)
          chip(
              Icons.access_time_rounded,
              _timeText(DateTime.now(), info.timeMode!),
              () => showTimeDialog(context, info, onChanged),
              () => info.timeMode = null),
      ],
    );
  }
}

// ---------------------------- العرض في القصة ----------------------------

Future<void> _open(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('تعذر فتح الرابط'))));
    }
  }
}

/// ملصقات المعلومات فوق القصة: رابط وموقع (قابلان للنقر)، وعدّ تنازلي، ووقت.
class StoryInfoRow extends StatelessWidget {
  final StoryInfo info;
  final DateTime createdAt;
  const StoryInfoRow({super.key, required this.info, required this.createdAt});

  Widget _pill(BuildContext context, IconData icon, String text,
      {VoidCallback? onTap}) {
    return Material(
      color: const Color(0xCCFFFFFF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.black87),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = info.linkUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (info.countdownAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StoryCountdown(
                title: info.countdownTitle ?? '', endMs: info.countdownAt!),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (info.timeMode != null)
              _pill(context, Icons.access_time_rounded,
                  _timeText(createdAt, info.timeMode!)),
            if (info.location != null)
              _pill(context, Icons.place_rounded, info.location!,
                  onTap: () => _open(
                      context,
                      Uri.https('www.google.com', '/maps/search/',
                          {'api': '1', 'query': info.location!}).toString())),
            if (url != null)
              _pill(
                  context,
                  Icons.link_rounded,
                  (info.linkLabel ?? '').isEmpty
                      ? (Uri.tryParse(url)?.host ?? url)
                      : info.linkLabel!,
                  onTap: () => _open(context, url)),
          ],
        ),
      ],
    );
  }
}

/// عدّ تنازلي حي بالأيام والساعات والدقائق والثواني.
class StoryCountdown extends StatefulWidget {
  final String title;
  final int endMs;
  const StoryCountdown({super.key, required this.title, required this.endMs});

  @override
  State<StoryCountdown> createState() => _StoryCountdownState();
}

class _StoryCountdownState extends State<StoryCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _unit(int v, String label) => Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(_two(v),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final left = DateTime.fromMillisecondsSinceEpoch(widget.endMs)
        .difference(DateTime.now());
    final done = left.isNegative || left == Duration.zero;
    final d = done ? Duration.zero : left;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 8),
          if (done)
            Text(tr('انتهى العدّ'),
                style: const TextStyle(color: Colors.white70, fontSize: 14))
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _unit(d.inDays, tr('يوم')),
                  _unit(d.inHours % 24, tr('ساعة')),
                  _unit(d.inMinutes % 60, tr('دقيقة')),
                  _unit(d.inSeconds % 60, tr('ثانية')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
