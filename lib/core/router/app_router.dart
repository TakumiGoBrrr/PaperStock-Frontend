import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../storage/storage_service.dart';
import '../widgets/glass_app_bar.dart';
import '../../features/auth/controller/auth_controller.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/feed/create_post_screen.dart';
import '../../features/feed/models/post.dart';
import '../../features/feed/feed_screen.dart';
import '../../features/feed/post_detail_screen.dart';
import '../../features/legal/community_guidelines_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/interests_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/recycle_bin_screen.dart';
import '../../features/qotd/qotd_controller.dart';
import '../../features/swipe/swipe_demo_screen.dart';
import '../../features/swipe/story_ad_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/search/tag_search_results_screen.dart';

CustomTransitionPage<T> _fadeScalePage<T>({
  required GoRouterState state,
  required Widget child,
  Duration duration = const Duration(milliseconds: 250),
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) async {
      final authValue = ref.read(authControllerProvider);
      final auth = authValue.valueOrNull;

      final storage = ref.read(storageServiceProvider);
      final token = await storage.read(key: 'access_token');
      final isLoggedIn = (auth?.isAuthenticated ?? false) ||
          (token != null && token.isNotEmpty);

      final path = state.uri.path;

      // Shared QOTD link landed on the web app as `/?q={id}&ref={uid}`.
      // Route it to the deep-link handler (which redeems + opens the Daily tab).
      final qParam = state.uri.queryParameters['q'];
      if (qParam != null &&
          qParam.isNotEmpty &&
          (path == '/' || path == '/home' || path == '/feed')) {
        if (!isLoggedIn) return '/login';
        final refParam = state.uri.queryParameters['ref'];
        return '/q/$qParam${refParam != null && refParam.isNotEmpty ? '?ref=$refParam' : ''}';
      }

      if (path == '/' || path == '/home') return '/feed';

      final isAuthRoute = path == '/login' ||
          path == '/register' ||
          path == '/otp' ||
          path == '/forgot-password' ||
          path == '/reset-password';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/feed';

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const LoginScreen(),
          );
        },
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final email = state.uri.queryParameters['email'];
          final password = state.uri.queryParameters['password'];
          return _fadeScalePage(
            state: state,
            child: RegisterScreen(
              initialEmail: email,
              initialPassword: password,
            ),
          );
        },
      ),
      GoRoute(
        path: '/otp',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          if (extra is! OtpArgs) {
            return _fadeScalePage(
              state: state,
              child: const LoginScreen(),
            );
          }

          return _fadeScalePage(
            state: state,
            child: OtpScreen(args: extra),
          );
        },
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const ForgotPasswordScreen(),
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          if (extra is! ResetPasswordArgs) {
            return _fadeScalePage(
              state: state,
              child: const LoginScreen(),
            );
          }

          return _fadeScalePage(
            state: state,
            child: ResetPasswordScreen(args: extra),
          );
        },
      ),
      GoRoute(
        path: '/interests',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const InterestsScreen(),
          );
        },
      ),
      GoRoute(
        path: '/swipe-demo',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const SwipeDemoScreen(),
          );
        },
      ),
      GoRoute(
        path: '/community-guidelines',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final isOnboarding =
              state.uri.queryParameters['onboarding'] == 'true';
          return _fadeScalePage(
            state: state,
            child: CommunityGuidelinesScreen(isOnboarding: isOnboarding),
          );
        },
      ),
      GoRoute(
        path: '/sponsored-story',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          if (extra is! StoryAdArgs) {
            return _fadeScalePage(state: state, child: const FeedScreen());
          }
          return _fadeScalePage(
            state: state,
            child: StoryAdScreen(args: extra),
          );
        },
      ),
      GoRoute(
        path: '/feed',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const FeedScreen(),
          );
        },
      ),
      GoRoute(
        path: '/qotd',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const _QotdEntryScreen(),
          );
        },
      ),
      GoRoute(
        path: '/q/:id',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: _QotdEntryScreen(
              questionId: state.pathParameters['id'],
              ref: state.uri.queryParameters['ref'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/post/create',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final postToEdit = state.extra as Post?;
          return _fadeScalePage(
            state: state,
            child: CreatePostScreen(postToEdit: postToEdit),
          );
        },
      ),
      GoRoute(
        path: '/post/:id',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          final authorId = extra is Map
              ? ((extra['authorId'] as Object?)?.toString() ?? '')
              : '';
          final authorName = extra is Map
              ? ((extra['authorName'] as Object?)?.toString() ?? '')
              : '';
          return _fadeScalePage(
            state: state,
            child: PostDetailScreen(
              postId: id,
              fallbackAuthorId: authorId,
              fallbackAuthorName: authorName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const EditProfileScreen(),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const SettingsScreen(),
          );
        },
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const HistoryScreen(),
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar: GlassAppBar(
                title: Text(
                  'Notifications',
                  style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                left: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
              ),
              body: SafeArea(
                bottom: false,
                child: const NotificationsScreen(),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/profile/me',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const ProfileScreen(
              userId: 'me',
            ),
          );
        },
      ),
      GoRoute(
        path: '/profile/:id',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final id = state.pathParameters['id'] ?? '';
          return _fadeScalePage(
            state: state,
            child: ProfileScreen(userId: id),
          );
        },
      ),
      GoRoute(
        path: '/recycle-bin',
        pageBuilder: (BuildContext context, GoRouterState state) {
          return _fadeScalePage(
            state: state,
            child: const RecycleBinScreen(),
          );
        },
      ),
      GoRoute(
        path: '/tag-search',
        pageBuilder: (BuildContext context, GoRouterState state) {
          final tags = state.extra is List<String>
              ? state.extra as List<String>
              : const <String>[];
          return _fadeScalePage(
            state: state,
            child: TagSearchResultsScreen(tags: tags),
          );
        },
      ),
    ],
    debugLogDiagnostics: kDebugMode,
  );
});

final _routerRefreshNotifierProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _sub = _ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthState>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// Handles `/qotd` and shared `/q/:id?ref=` deep links: records challenge
/// attribution (best-effort) and opens the feed shell on the "Daily" tab.
class _QotdEntryScreen extends ConsumerStatefulWidget {
  const _QotdEntryScreen({this.questionId, this.ref});

  final String? questionId;
  final String? ref;

  @override
  ConsumerState<_QotdEntryScreen> createState() => _QotdEntryScreenState();
}

class _QotdEntryScreenState extends ConsumerState<_QotdEntryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Open the Daily tab inside the feed shell.
      ref.read(bottomNavIndexProvider.notifier).state = 1;

      // Best-effort challenge attribution.
      final qid = widget.questionId;
      final refUid = widget.ref;
      if (qid != null && qid.isNotEmpty && refUid != null && refUid.isNotEmpty) {
        await ref
            .read(qotdRepositoryProvider)
            .redeemChallenge(questionId: qid, ref: refUid);
        ref.invalidate(qotdControllerProvider);
      }

      if (mounted) context.go('/feed');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
