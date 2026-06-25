// Cross-platform PWA helpers. The web implementation talks to JS hooks defined
// in web/index.html; the stub is used on native builds (where there's no PWA).
export 'pwa_support_stub.dart' if (dart.library.js_interop) 'pwa_support_web.dart';
