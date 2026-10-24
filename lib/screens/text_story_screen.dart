import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import 'close_friends_screen.dart';
import 'story_backgrounds.dart';
import 'story_mentions.dart';
import 'story_movable.dart';
import 'story_poll.dart';
import 'story_question.dart';
import 'story_info.dart';
import 'story_slider.dart';

/// قصة نصية بخلفية ملونة (مثل إنستغرام): اكتب نصاً واختر لون الخلفية.
class TextStoryScreen extends StatefulWidget {
  const TextStoryScreen({super.key});

  @override
  State<TextStoryScreen> createState() => _TextStoryScreenState();
}

class _TextStoryScreenState extends State<TextStoryScreen> {
  static const _maxChars = 250;
  final _text = TextEditingController();
  int _bg = 0;
  StoryPoll? _poll;
  StoryQuestion? _question;
  StorySlider? _slider;
  final StoryInfo _info = StoryInfo();
  final List<StoryMention> _mentions = [];
  bool _closeFriends = false; // القصة للأصدقاء المقربين فقط
  bool _busy = false;
  bool _dialogOpen = false; // نافذة مفتوحة: نجمّد حجم الصفحة
  String? _error;

  void _setDialogOpen(bool v) {
    if (mounted && _dialogOpen != v) setState(() => _dialogOpen = v);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _editSlider() async {
    final r = await showSliderDialog(context,
        initial: _slider, onOpen: _setDialogOpen);
    if (r != null && mounted) {
      setState(() => _slider = r.placedLike(_slider, kSliderDefY));
    }
  }

  Future<void> _editQuestion() async {
    final q = await showQuestionDialog(context,
        initial: _question, onOpen: _setDialogOpen);
    if (q != null && mounted) {
      setState(() => _question = q.placedLike(_question, kQuestionDefY));
    }
  }

  Future<void> _editPoll() async {
    final p = await showPollDialog(context,
        initial: _poll, onOpen: _setDialogOpen);
    if (p != null && mounted) {
      setState(() => _poll = p.placedLike(_poll, kPollDefY));
    }
  }

  Future<void> _publish() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = tr('اكتب شيئاً أولاً'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.publishTextStory(text, _bg,
          poll: _poll,
          question: _question,
          slider: _slider,
          info: _info.isEmpty ? null : _info,
          mentions: List.of(_mentions),
          closeFriends: _closeFriends);
      if (_mentions.isNotEmpty) {
        unawaited(notifyStoryMentions(List.of(_mentions)));
      }
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(tr('تمت إضافة القصة'))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, fallback: tr('فشل النشر'));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: !_dialogOpen,
      body: Container(
        decoration: BoxDecoration(gradient: storyGradient(_bg)),
        child: Stack(
          children: [
            SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          size: 28, color: Colors.white),
                    ),
                    const Spacer(),
                    StoryInfoMenu(
                        info: _info,
                        color: Colors.white,
                        onChanged: () => setState(() {})),
                    IconButton(
                      onPressed: _busy ? null : _editSlider,
                      tooltip: tr('شريط إيموجي'),
                      icon: const Icon(Icons.linear_scale_rounded,
                          size: 26, color: Colors.white),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _editQuestion,
                      tooltip: tr('صندوق أسئلة'),
                      icon: const Icon(Icons.help_outline_rounded,
                          size: 26, color: Colors.white),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _editPoll,
                      tooltip: tr('استطلاع'),
                      icon: const Icon(Icons.poll_outlined,
                          size: 26, color: Colors.white),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _publish,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(tr('إضافة'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      enabled: !_busy,
                      textAlign: TextAlign.center,
                      minLines: 1,
                      maxLines: 8,
                      maxLength: _maxChars,
                      cursorColor: Colors.white,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.4),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        hintText: tr('اكتب قصتك...'),
                        hintStyle: const TextStyle(
                            color: Colors.white60,
                            fontSize: 28,
                            fontWeight: FontWeight.w700),
                      ),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StoryAudienceSelector(
                    close: _closeFriends,
                    enabled: !_busy,
                    color: Colors.white,
                    onChanged: (v) {
                      if (mounted) setState(() => _closeFriends = v);
                    }),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: MentionEditor(
                    mentions: _mentions,
                    enabled: !_busy,
                    color: Colors.white,
                    onChanged: () {
                      if (mounted) setState(() {});
                    }),
              ),
              if (!_info.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StoryInfoChips(
                      info: _info,
                      enabled: !_busy,
                      onChanged: () => setState(() {})),
                ),
              if (_slider != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.linear_scale_rounded, size: 18),
                    label: Text(
                        _slider!.q.isEmpty ? _slider!.e : '${_slider!.e} ${_slider!.q}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _busy ? null : _editSlider,
                    onDeleted:
                        _busy ? null : () => setState(() => _slider = null),
                  ),
                ),
              if (_question != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.help_outline_rounded, size: 18),
                    label: Text(_question!.q,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _busy ? null : _editQuestion,
                    onDeleted:
                        _busy ? null : () => setState(() => _question = null),
                  ),
                ),
              if (_poll != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.poll_outlined, size: 18),
                    label: Text(_poll!.q,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _busy ? null : _editPoll,
                    onDeleted:
                        _busy ? null : () => setState(() => _poll = null),
                  ),
                ),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: storyBgCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: _busy ? null : () => setState(() => _bg = i),
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: storyGradient(i),
                          border: Border.all(
                              color: Colors.white,
                              width: i == _bg ? 3 : 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
            ),
            // الاستطلاع والأسئلة والشريط: اسحبها لتضعها أينما تريد على القصة.
            Positioned.fill(
              child: StoryCardsLayer(
                poll: _poll,
                question: _question,
                slider: _slider,
                enabled: !_busy,
                onPoll: (v) => setState(() => _poll = v),
                onQuestion: (v) => setState(() => _question = v),
                onSlider: (v) => setState(() => _slider = v),
                onEditPoll: _editPoll,
                onEditQuestion: _editQuestion,
                onEditSlider: _editSlider,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
