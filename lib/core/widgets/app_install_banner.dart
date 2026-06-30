import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../pwa/pwa_support.dart';

/// Shown to logged-in users on the **web** who are NOT running the installed
/// app / home-screen web-clip ("app mode"). Offers a one-tap install and a
/// dismiss (×). Renders nothing on native or when already installed.
class AppInstallBanner extends StatefulWidget {
  const AppInstallBanner({super.key});

  @override
  State<AppInstallBanner> createState() => _AppInstallBannerState();
}

class _AppInstallBannerState extends State<AppInstallBanner> {
  bool _dismissed = false;

  void _onInstall() {
    // Chrome / Edge / Android, when the browser exposes a prompt: one-tap install
    // (adds the PWA to the home screen, opens standalone like a native app).
    if (pwaCanInstall()) {
      pwaPromptInstall();
      return;
    }
    // Otherwise (iOS Safari, or browsers without a prompt) show the platform's
    // "Add to Home Screen" steps.
    _showInstallInstructions(pwaInstallPlatform());
  }

  void _showInstallInstructions(String platform) {
    final (String title, String subtitle, List<String> steps) = _instructionsFor(platform);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(title, style: GoogleFonts.lora(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(subtitle, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 10 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${i + 1}.', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: cs.primary)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(steps[i], style: GoogleFonts.inter(fontSize: 13, height: 1.45))),
                    ],
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
          ],
        );
      },
    );
  }

  (String, String, List<String>) _instructionsFor(String platform) {
    switch (platform) {
      case 'ios-safari':
        return (
          'Install on iPhone',
          'Add PaperStock to your home screen:',
          <String>[
            'Tap the Share button at the bottom of Safari (the square with an up arrow).',
            "Scroll down and select 'Add to Home Screen'.",
            "Tap 'Add' in the top-right corner.",
          ],
        );
      case 'ios-other':
        return (
          'Open in Safari',
          'To install on iPhone you need to use Safari:',
          <String>[
            'Open paperstock.app in the Safari app.',
            'Tap the Share button at the bottom of Safari.',
            "Select 'Add to Home Screen'.",
          ],
        );
      case 'mac-safari':
        return (
          'Install PaperStock',
          'Add PaperStock to your Dock:',
          <String>[
            'Click the Share button in the Safari toolbar.',
            "Select 'Add to Dock'.",
            'Confirm the installation.',
          ],
        );
      default:
        return (
          'Install PaperStock',
          'Add PaperStock to your home screen:',
          <String>[
            'Open your browser menu (the three dots in the corner).',
            "Select 'Install app' or 'Add to Home screen'.",
            'Confirm the installation.',
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed || pwaIsStandalone()) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.add_to_home_screen_rounded, size: 20, color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Add PaperStock to your home screen',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _onInstall,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Install'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
                icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onPrimaryContainer),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
