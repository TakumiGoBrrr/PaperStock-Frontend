import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/card_brightness_provider.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isCardDark = brightness == Brightness.dark;

    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns:
                Tween<double>(begin: 0.75, end: 1.0).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Icon(
          isCardDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          key: ValueKey<bool>(isCardDark),
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      tooltip: isCardDark ? 'Cards: switch to light' : 'Cards: switch to dark',
      onPressed: () => ref.read(cardBrightnessProvider.notifier).toggle(),
    );
  }
}
