import 'package:flutter/material.dart';

import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _saving = false;
  String? _error;

  static const _slides = [
    _OnboardingSlide(
      icon: Icons.play_circle_fill_rounded,
      title: 'لحظات قصيرة، حكايات كثيرة',
      description:
          'اكتشف فيديوهات قصيرة تناسب اهتماماتك، ومرّر للأعلى لتجد حكاية جديدة.',
    ),
    _OnboardingSlide(
      icon: Icons.dynamic_feed_rounded,
      title: 'تابع ما يهمك',
      description:
          'تصفّح المنشورات والقصص، وتواصل مع صُنّاع المحتوى الذين تحبهم.',
    ),
    _OnboardingSlide(
      icon: Icons.add_a_photo_rounded,
      title: 'شارك لمحتك',
      description:
          'أنشئ منشوراً أو قصة أو ريلز، واجعل لحظاتك جزءاً من مجتمع Haigram.',
    ),
  ];

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'تعذر حفظ إعداد البداية. تحقق من مساحة التخزين ثم حاول مرة أخرى.';
        });
      }
    }
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [AppPalette.dark.bg2, AppPalette.dark.bg, AppPalette.dark.bg]
                : [
                    AppPalette.light.surfaceHigh,
                    AppPalette.light.bg,
                    AppPalette.light.bg
                  ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    const LamhaLogo(size: 40),
                    const SizedBox(width: 10),
                    const HaigramWordmark(
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_page < _slides.length - 1)
                      TextButton(
                        onPressed: _saving ? null : _finish,
                        child: const Text('تخطي'),
                      ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (index) => setState(() => _page = index),
                    itemBuilder: (context, index) =>
                        _SlideView(slide: _slides[index]),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: index == _page ? 24 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color:
                            index == _page ? AppColors.accent2 : Colors.white24,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (_error != null) ...[
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.appColors.text)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _saving ? null : _next,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_page == _slides.length - 1
                          ? 'ابدأ رحلتك'
                          : 'التالي'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Column(
        key: ValueKey(slide.title),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, AppColors.accent2],
              ),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withOpacity(0.24),
                    blurRadius: 60,
                    spreadRadius: 8),
              ],
            ),
            child: Icon(slide.icon, size: 112, color: Colors.white),
          ),
          const SizedBox(height: 48),
          Text(slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              slide.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appColors.textDim, fontSize: 16, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }
}
