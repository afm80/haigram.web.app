import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import 'story_dialog.dart';
import '../services/post_service.dart';

/// نافذة إنشاء الاستطلاع: سؤال وخياران. تعيد null عند الإلغاء.
Future<StoryPoll?> showPollDialog(BuildContext context,
    {StoryPoll? initial, ValueChanged<bool>? onOpen}) {
  return showStoryDialog<StoryPoll>(
    context,
    (_) => _PollDialog(initial: initial),
    onOpen: onOpen,
  );
}

class _PollDialog extends StatefulWidget {
  final StoryPoll? initial;
  const _PollDialog({this.initial});

  @override
  State<_PollDialog> createState() => _PollDialogState();
}

class _PollDialogState extends State<_PollDialog> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initial?.q ?? '');
  late final TextEditingController _a =
      TextEditingController(text: widget.initial?.a ?? tr('نعم'));
  late final TextEditingController _b =
      TextEditingController(text: widget.initial?.b ?? tr('لا'));
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _done() {
    final q = _q.text.trim();
    final a = _a.text.trim();
    final b = _b.text.trim();
    if (q.isEmpty || a.isEmpty || b.isEmpty) {
      setState(() => _error = tr('املأ السؤال والخيارين'));
      return;
    }
    Navigator.of(context).pop(StoryPoll(q: q, a: a, b: b));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('استطلاع')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              maxLength: 100,
              decoration: InputDecoration(labelText: tr('السؤال')),
            ),
            TextField(
              controller: _a,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('الخيار الأول')),
            ),
            TextField(
              controller: _b,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('الخيار الثاني')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('إلغاء'))),
        FilledButton(onPressed: _done, child: Text(tr('تم'))),
      ],
    );
  }
}

/// بطاقة الاستطلاع فوق القصة: للمشاهد أزرار التصويت ثم النسب،
/// ولصاحب القصة النتائج مباشرة.
class StoryPollCard extends StatefulWidget {
  final Post story;
  final StoryPoll poll;
  final bool mine;
  const StoryPollCard(
      {super.key, required this.story, required this.poll, required this.mine});

  @override
  State<StoryPollCard> createState() => _StoryPollCardState();
}

class _StoryPollCardState extends State<StoryPollCard> {
  int? _my; // تصويتي (0 أو 1)
  List<int>? _counts; // عدد أصوات كل خيار
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<int>?> _safeCounts() async {
    try {
      return await PostService.pollCounts(widget.story.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    int? my;
    if (!widget.mine) {
      try {
        my = await PostService.myPollVote(widget.story.id);
      } catch (_) {
        my = null;
      }
    }
    final counts = (widget.mine || my != null) ? await _safeCounts() : null;
    if (!mounted) return;
    setState(() {
      _my = my;
      _counts = counts;
    });
  }

  Future<void> _vote(int choice) async {
    if (_busy || widget.mine || _my != null) return;
    if (needsLogin(context)) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.votePoll(widget.story.id, choice);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذر التصويت'))));
      return;
    }
    if (!mounted) return;
    setState(() {
      _my = choice;
      _busy = false;
    });
    final counts = await _safeCounts();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  bool get _showResults => widget.mine || _my != null;

  Widget _option(int i, String label) {
    if (!_showResults) {
      return Material(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _vote(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ),
      );
    }
    final c = _counts;
    final total = c == null ? 0 : c[0] + c[1];
    final pct = (c == null || total == 0) ? 0.0 : c[i] / total;
    final chosen = _my == i;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
                color: chosen ? const Color(0x33FFFFFF) : const Color(0x1AFFFFFF)),
          ),
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: pct,
                child: ColoredBox(
                    color: chosen
                        ? const Color(0x99FFFFFF)
                        : const Color(0x55FFFFFF),
                    child: const SizedBox.expand()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (chosen)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 6),
                    child: Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                  ),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                if (c != null)
                  Text('${(pct * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.poll;
    final c = _counts;
    final total = c == null ? 0 : c[0] + c[1];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.q,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.3)),
          const SizedBox(height: 10),
          if (_showResults) ...[
            _option(0, p.a),
            const SizedBox(height: 8),
            _option(1, p.b),
            if (c != null) ...[
              const SizedBox(height: 8),
              Text(trf('{0} صوت', [total]),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ] else
            Row(
              children: [
                Expanded(child: _option(0, p.a)),
                const SizedBox(width: 8),
                Expanded(child: _option(1, p.b)),
              ],
            ),
        ],
      ),
    );
  }
}
