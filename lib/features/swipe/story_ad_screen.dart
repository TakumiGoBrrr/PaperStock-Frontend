import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/glass_app_bar.dart';

/// Arguments for the story-style ad reader.
class StoryAdArgs {
  const StoryAdArgs({
    required this.adId,
    required this.title,
    required this.body,
    required this.targetUrl,
    this.onLearnMore,
  });

  final String adId;
  final String title;
  final String body;
  final String? targetUrl;

  /// Called when the user taps the "Learn more" CTA (used to record a click).
  final void Function(String adId)? onLearnMore;
}

/// Full-screen reader for a story-style ad: shows the complete story body with
/// a "Learn more" call-to-action link at the end.
class StoryAdScreen extends StatelessWidget {
  const StoryAdScreen({super.key, required this.args});

  final StoryAdArgs args;

  Future<void> _learnMore(BuildContext context) async {
    final url = args.targetUrl;
    if (url == null || url.isEmpty) return;
    args.onLearnMore?.call(args.adId);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasLink = (args.targetUrl ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        title: Text(
          'Sponsored',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        left: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.campaign_outlined,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      'Sponsored story',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                args.title,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 18),
              MarkdownBody(
                data: args.body,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: GoogleFonts.inter(
                    fontSize: 16,
                    height: 1.7,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (hasLink) ...<Widget>[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _learnMore(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Learn more'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
