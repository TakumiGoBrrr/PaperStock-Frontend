// Native build: there is no PWA. Report "already installed" so the web-only
// install banner never shows, and make the install action a no-op.
bool pwaIsStandalone() => true;
bool pwaCanInstall() => false;
void pwaPromptInstall() {}
String pwaInstallPlatform() => 'other';
bool pwaIsAndroid() => false;
void pwaDownloadApk() {}
