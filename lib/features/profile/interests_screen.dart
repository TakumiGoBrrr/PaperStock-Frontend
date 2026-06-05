import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/widgets/notification_bell_button.dart';

class InterestsScreen extends ConsumerStatefulWidget {
  const InterestsScreen({super.key});

  @override
  ConsumerState<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends ConsumerState<InterestsScreen> {
  bool _isSaving = false;
  String? _error;

  List<String> _suggested = const <String>[];
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadTrendingTags());
  }

  Dio get _dio => ref.read(apiClientProvider).dio;

  Future<void> _loadTrendingTags() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search/trending-tags',
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is List) ? (body['data'] as List) : const [];

      final tags = data
          .map((e) => _normalizeTag(e.toString()))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _suggested = tags);
    } catch (_) {
      // Optional UI; ignore failures.
    }
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else {
        if (_selected.length >= 10) return;
        _selected.add(tag);
      }
      _error = null;
    });
  }

  Future<void> _skip() async {
    if (!mounted) return;
    context.go('/swipe-demo');
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_selected.isEmpty) {
      await _skip();
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await _dio.patch<Map<String, dynamic>>(
        '/api/v1/users/me',
        data: <String, dynamic>{
          'interests': _selected.toList(growable: false),
        },
      );

      if (!mounted) return;
      context.go('/swipe-demo');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.response?.data?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final chips = <String>{..._suggested, ..._selected}.toList(growable: false)
      ..sort();
    final visibleChips = chips.take(20).toList(growable: false);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        title: Text(
          'PaperStock',
          style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        left: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        right: const NotificationBellButton(),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Pick your interests',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This helps personalize your For You feed. You can change this later.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (chips.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Center(
                        child: Text(
                          'Loading tags…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: visibleChips.map((tag) {
                            final isSelected = _selected.contains(tag);
                            return FilterChip(
                              label: Text('#$tag'),
                              selected: isSelected,
                              selectedColor:
                                  colorScheme.primary.withValues(alpha: 0.20),
                              checkmarkColor:
                                  theme.brightness == Brightness.dark
                                      ? colorScheme.secondary
                                      : null,
                              onSelected: (_) => _toggle(tag),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (_error != null)
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.error),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_selected.isEmpty ? 'Skip' : 'Continue'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isSaving ? null : _skip,
                    child: const Text('Skip for now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _normalizeTag(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final noHash = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  return noHash.trim().toLowerCase();
}
