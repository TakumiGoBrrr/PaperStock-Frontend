// Web implementation — bridges to the JS hooks installed in web/index.html.
import 'dart:js_interop';

@JS('__isStandalone')
external bool _isStandalone();

@JS('__canInstallPWA')
external bool _canInstall();

@JS('__promptInstall')
external void _promptInstall();

@JS('__installPlatform')
external String _installPlatform();

@JS('__isAndroid')
external bool _isAndroid();

@JS('__downloadAndroidApk')
external void _downloadAndroidApk();

/// True when running as an installed PWA / home-screen web-clip ("app mode").
bool pwaIsStandalone() {
  try {
    return _isStandalone();
  } catch (_) {
    return false;
  }
}

/// True when the browser captured an install prompt we can trigger (Chrome/Edge).
bool pwaCanInstall() {
  try {
    return _canInstall();
  } catch (_) {
    return false;
  }
}

/// Triggers the browser's install prompt if one is available.
void pwaPromptInstall() {
  try {
    _promptInstall();
  } catch (_) {}
}

/// Platform hint ('ios-safari', 'ios-other', 'mac-safari', 'other') used to
/// pick manual install instructions when no native prompt is available.
String pwaInstallPlatform() {
  try {
    return _installPlatform();
  } catch (_) {
    return 'other';
  }
}

/// True on Android browsers, where we hand out the native APK instead of a PWA.
bool pwaIsAndroid() {
  try {
    return _isAndroid();
  } catch (_) {
    return false;
  }
}

/// Triggers a download of the signed Android APK.
void pwaDownloadApk() {
  try {
    _downloadAndroidApk();
  } catch (_) {}
}
