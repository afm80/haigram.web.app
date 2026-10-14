import 'package:flutter/material.dart';

import '../theme.dart';

/// تبويب «غرف صوتية»: صفحة مؤقتة تُطوَّر لاحقاً.
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: EmptyState(
        icon: Icons.mic_none_rounded,
        title: 'غرف صوتية',
        message: 'ستتوفر الغرف الصوتية قريباً.',
      ),
    );
  }
}
