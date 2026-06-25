# PaperStock Frontend — Agent Guide

Flutter app for PaperStock ("Hinge for short stories"). Ships as **Android APK**
and a **Flutter web build** (the web build is also what iOS users run as an Apple
**Web Clip / PWA** — there is NO native iOS target, no `ios/` folder).

## This is its own git repo
Separate from the backend (origin `TakumiGoBrrr/PaperStock-Frontend`). The parent
backend repo gitignores `frontend/`. Workflow: develop on **`experimental`**, then
merge into **`main`** and push.

## Architecture
- State: **Riverpod**. Nav: **go_router** (`lib/core/router/app_router.dart`). HTTP: **Dio** via `apiClientProvider` (`lib/core/api/`); base URL defaults to `https://paperstock.app`, prefix `/api/v1`.
- Feature pattern (mirror `features/swipe/`): `*_repository.dart` (Dio calls) + `*_controller.dart` (`AutoDisposeAsyncNotifier` exposing an immutable state) + screens.
- Bottom nav lives in `features/feed/feed_screen.dart` (`bottomNavIndexProvider`). Tabs: **0 Discover · 1 Daily(QOTD) · 2 Bookmarks · 3 Profile** — keep the hardcoded index checks in that file in sync if you reorder.
- Web uses **path URL strategy** (`usePathUrlStrategy()` in `main.dart`) so query params survive; the server has an SPA fallback for clean URLs.

## Run / build
- `flutter pub get`, `flutter run`, `flutter analyze` (keep it clean before committing).
- Web: `flutter build web`. APK: `flutter build apk`. Deploy is manual — publish the web build to the server web root `/var/www/paperstock` (backend repo's `deploy_backend.py` does NOT touch the frontend).

## Question of the Day (`features/qotd/`)
- "Daily" tab: question header → answer composer (deck of others' answers loads only after you answer) → swipe deck (right=heart, left=skip) → "Challenge a friend" (`share_plus` → deep link `…/q/{id}?ref={myUid}`).
- Deep links: routes `/qotd` and `/q/:id` in `app_router.dart`; `app_links` feeds incoming Android App Link intents to go_router; `_QotdEntryScreen` redeems `?ref=` and opens the Daily tab.
- Daily reminder: `lib/core/notifications/local_notifications_service.dart` — **Android-only** local notification (guarded by `kIsWeb`/`defaultTargetPlatform`); Settings has the toggle. No FCM/web-push.

## Gotchas
- `flutter_local_notifications` is mobile-only — always guard with `LocalNotificationsService.instance.isSupported` before use.
- The swipe controllers track `_swipedThisSession` to stop low-deck refills re-adding a just-swiped card before the server records the swipe — preserve that when editing deck logic.
