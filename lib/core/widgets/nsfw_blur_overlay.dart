import 'dart:ui';

import 'package:flutter/material.dart';

import '../storage/nsfw_consent_store.dart';

/// A blur overlay widget that requires 18+ age confirmation to view NSFW content.
class NsfwBlurOverlay extends StatefulWidget {
  const NsfwBlurOverlay({
    super.key,
    required this.child,
    required this.isNsfw,
    this.borderRadius,
  });

  final Widget child;
  final bool isNsfw;

  /// Optional rounded-corner radius used to clip the blur + overlay so it stays
  /// contained within the child's shape (e.g. a swipe card) instead of bleeding
  /// across the whole screen.
  final BorderRadius? borderRadius;

  @override
  State<NsfwBlurOverlay> createState() => _NsfwBlurOverlayState();
}

class _NsfwBlurOverlayState extends State<NsfwBlurOverlay> {
  bool _hasConfirmed = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfirmation();
  }

  Future<void> _loadConfirmation() async {
    final confirmed = await NsfwConsentStore.hasConfirmed18Plus();
    if (mounted) {
      setState(() {
        _hasConfirmed = confirmed;
        _isLoading = false;
      });
    }
  }

  Future<void> _showConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Flexible(child: Text('NSFW Content Warning')),
          ],
        ),
        content: const Text(
          'This post contains content that is Not Safe For Work (NSFW). '
          'It may include mature themes, explicit material, or sensitive content.\n\n'
          'You must be 18 years or older to view this content.\n\n'
          'Are you 18 years or older?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, I\'m 18+'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await NsfwConsentStore.setConfirmed18Plus(true);
      if (mounted) {
        setState(() {
          _hasConfirmed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If not NSFW content, just show the child
    if (!widget.isNsfw) {
      return widget.child;
    }

    // If loading, show loading indicator with blur
    if (_isLoading) {
      return _clip(
        Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: widget.child,
            ),
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        ),
      );
    }

    // If confirmed, show content without blur
    if (_hasConfirmed) {
      return widget.child;
    }

    // Show blurred content with confirmation button
    return _clip(
      Stack(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: widget.child,
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 48,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'NSFW Content',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'This content may not be suitable for all audiences',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _showConfirmationDialog,
                              icon: const Icon(Icons.remove_red_eye),
                              label: const Text('View Content (18+)'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Clips the blurred content to [widget.borderRadius] when provided so the
  /// blur stays inside the card bounds instead of spilling onto the page.
  Widget _clip(Widget child) {
    if (widget.borderRadius == null) {
      return child;
    }
    return ClipRRect(
      borderRadius: widget.borderRadius!,
      child: child,
    );
  }
}
