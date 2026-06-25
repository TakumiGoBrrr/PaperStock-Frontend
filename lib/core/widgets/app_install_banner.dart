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
    if (pwaCanInstall()) {
      pwaPromptInstall();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In your browser menu, choose "Add to Home screen" to install the app.'),
          behavior: SnackBarBehavior.floating,
        ),
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
              Icon(Icons.download_rounded, size: 20, color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Get the PaperStock app',
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
                child: const Text('Download'),
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
