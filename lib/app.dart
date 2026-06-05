import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/network_status_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    final themeMode =
        ref.watch(themeControllerProvider).valueOrNull ?? ThemeMode.dark;

    return MaterialApp.router(
      title: 'PaperStock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: ref.watch(goRouterProvider),
      builder: (context, child) {
        return Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            if (isOffline) const _OfflineBanner(),
          ],
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: true,
        child: SafeArea(
          bottom: false,
          child: Material(
            color: colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'No internet',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
