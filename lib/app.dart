import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/network_status_provider.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  AppLinks? _appLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Daily reminder (Android-only; no-op elsewhere). Tapping it opens the
    // Daily tab via the router.
    await LocalNotificationsService.instance.init(
      onTap: (payload) {
        final target = (payload != null && payload.isNotEmpty) ? payload : '/qotd';
        ref.read(goRouterProvider).go(target);
      },
    );

    // Incoming App Link intents (Android). On web, GoRouter already consumes
    // the browser URL, so skip to avoid double handling.
    if (!kIsWeb) {
      _appLinks = AppLinks();
      try {
        final initial = await _appLinks!.getInitialLink();
        if (initial != null) _handleUri(initial);
      } catch (_) {}
      _appLinks!.uriLinkStream.listen(_handleUri, onError: (_) {});
    }
  }

  void _handleUri(Uri uri) {
    if (uri.host != 'paperstock.app') return;
    final path = uri.path;
    if (path.isEmpty) return;
    final target = uri.hasQuery ? '$path?${uri.query}' : path;
    ref.read(goRouterProvider).go(target);
  }

  @override
  Widget build(BuildContext context) {
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
