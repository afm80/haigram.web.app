import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../l10n.dart';
import '../services/post_service.dart';
import '../theme.dart';

/// نافذة إنشاء صندوق الأسئلة: عبارة قصيرة يجيب عنها المشاهدون. تعيد null عند الإلغاء.
Future<StoryQuestion?> showQuestionDialog(BuildContext context,
    {StoryQuestion? initial}) {
  return showDialog<StoryQuestion>(
    context: context,
    builder: (_) => _QuestionDialog(initial: initial),
  );
}

class _QuestionDialog extends StatefulWidget {
  final StoryQuestion? initial;
  const _QuestionDialog({this.initial});

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final TextEditingController _q =
      TextEditingController(text: widget.initial?.q ?? tr('اسألني أي شيء'));
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _done() {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _error = tr('اكتب العبارة أولاً'));
      return;
    }
    Navigator.of(context).pop(StoryQuestion(q: q));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('صندوق أسئلة')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            maxLength: 100,
            decoration: InputDecoration(labelText: tr('العبارة')),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!),
            ),
        ],
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

/// بطاقة صندوق الأسئلة فوق القصة: للمشاهد خانة إجابة وزر إرسال،
/// ولصاحب القصة عدد الإجابات وزر لعرضها.
class StoryQuestionCard extends StatefulWidget {
  final Post story;
  final StoryQuestion question;
  final bool mine;

  /// يُستدعى بـ true عند بدء الكتابة أو فتح الإجابات وfalse عند انتهائها،
  /// ليوقف المشاهد العدّاد.
  final ValueChanged<bool>? onPause;
  const StoryQuestionCard(
      {super.key,
      required this.story,
      required this.question,
      required this.mine,
      this.onPause});

  @override
  State<StoryQuestionCard> createState() => _StoryQuestionCardState();
}

class _StoryQuestionCardState extends State<StoryQuestionCard> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _answered = false;
  bool _busy = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onPause?.call(_focus.hasFocus));
    _load();
  }

  @override
  void dispose() {
    // لا نستدعي setState الأب أثناء الإزالة: نؤجّل رفع الإيقاف لما بعد الإطار.
    if (_focus.hasFocus) {
      final cb = widget.onPause;
      WidgetsBinding.instance.addPostFrameCallback((_) => cb?.call(false));
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.mine) {
        final n = await PostService.answerCount(widget.story.id);
        if (mounted) setState(() => _count = n);
      } else {
        final a = await PostService.hasAnswered(widget.story.id);
        if (mounted) setState(() => _answered = a);
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_busy || _answered || widget.mine) return;
    if (needsLogin(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await PostService.answerQuestion(widget.story.id, text);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('تعذر إرسال الإجابة'))));
      return;
    }
    if (!mounted) return;
    _focus.unfocus();
    setState(() {
      _answered = true;
      _busy = false;
    });
  }

  Future<void> _showAnswers() async {
    widget.onPause?.call(true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AnswersSheet(story: widget.story),
    );
    widget.onPause?.call(false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(q.q,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.3)),
          const SizedBox(height: 10),
          if (widget.mine)
            Material(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showAnswers,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.question_answer_outlined,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(trf('{0} إجابة · عرض', [_count]),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
            )
          else if (_answered)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(tr('تم إرسال إجابتك'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(12)),
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      readOnly: !isLoggedIn,
                      onTap: () {
                        if (!isLoggedIn) needsLogin(context);
                      },
                      maxLength: PostService.maxAnswerLength,
                      maxLines: 2,
                      minLines: 1,
                      cursorColor: Colors.white,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: tr('اكتب إجابتك...'),
                        hintStyle: const TextStyle(color: Colors.white70),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded,
                            color: Colors.white),
                      ),
              ],
            ),
        ],
      ),
    );
  }
}

/// قائمة إجابات القصة (لصاحبها فقط).
class _AnswersSheet extends StatelessWidget {
  final Post story;
  const _AnswersSheet({required this.story});

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return tr('الآن');
    if (d.inMinutes < 60) return trf('منذ {0} د', [d.inMinutes]);
    return trf('منذ {0} س', [d.inHours]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(story.question?.q ?? tr('الإجابات'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Expanded(
            child: StreamBuilder<List<StoryAnswer>>(
              stream: PostService.storyAnswers(story.id),
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (list.isEmpty) {
                  return Center(
                    child: Text(tr('لا توجد إجابات بعد'),
                        style: TextStyle(color: colors.textDim)),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = list[i];
                    return ListTile(
                      title: Text(a.text),
                      subtitle: Text(
                          '@${a.username} · ${_ago(a.at)}',
                          style: TextStyle(color: colors.textDim, fontSize: 12)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
