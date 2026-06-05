import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/widgets/notification_bell_button.dart';
import 'controller/profile_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  String? _myId;
  List<String> _suggested = const <String>[];
  final Set<String> _selected = <String>{};

  Dio get _dio => ref.read(apiClientProvider).dio;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await _dio.get<Map<String, dynamic>>('/api/v1/users/me');
      final body = me.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};

      final id = (data['id'] as Object?)?.toString();
      final displayName = (data['display_name'] as Object?)?.toString();
      final bio = (data['bio'] as Object?)?.toString();

      final interestsJson = (data['interests'] is List)
          ? (data['interests'] as List)
          : const <dynamic>[];

      final interests = interestsJson
          .map((e) => _normalizeTag(e.toString()))
          .where((e) => e.isNotEmpty)
          .toSet();

      if (!mounted) return;

      _myId = (id == null || id.isEmpty) ? null : id;
      _displayNameController.text = (displayName ?? '').trim();
      _bioController.text = (bio ?? '').trim();
      _selected
        ..clear()
        ..addAll(interests);

      setState(() {
        _isLoading = false;
        _error = null;
      });

      unawaited(_loadTrendingTags());
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.response?.data?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

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
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();

    final data = <String, dynamic>{
      'display_name': displayName.isEmpty ? null : displayName,
      'bio': bio.isEmpty ? null : bio,
      if (_selected.isNotEmpty) 'interests': _selected.toList(growable: false),
    };

    try {
      await _dio.patch<Map<String, dynamic>>('/api/v1/users/me', data: data);

      final id = _myId;
      if (id != null && id.isNotEmpty) {
        ref.invalidate(profileControllerProvider(id));
      }

      if (!mounted) return;
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      final responseData = e.response?.data;
      final detail = (responseData is Map)
          ? responseData['detail']?.toString()
          : null;

      String errorMsg;
      if (statusCode == 409) {
        errorMsg = detail ?? 'That display name is already taken.';
      } else if (detail != null && detail.trim().isNotEmpty) {
        errorMsg = detail;
      } else {
        errorMsg = e.message ?? 'Failed to save. Please try again.';
      }

      setState(() {
        _isSaving = false;
        _error = errorMsg;
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomInset),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: _isLoading
                        ? const Center(
                            child: SizedBox(
                              height: 28,
                              width: 28,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.6),
                            ),
                          )
                        : _error != null
                            ? _ErrorView(message: _error!, onRetry: _load)
                            : Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Text(
                                      'Edit Profile',
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _displayNameController,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: 'Display name',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _bioController,
                                      maxLines: 4,
                                      decoration: const InputDecoration(
                                        labelText: 'Bio',
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Interests (up to 10)',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: chips.map((tag) {
                                        final isSelected =
                                            _selected.contains(tag);
                                        return FilterChip(
                                          label: Text('#$tag'),
                                          selected: isSelected,
                                          onSelected: _isSaving
                                              ? null
                                              : (_) => _toggle(tag),
                                        );
                                      }).toList(growable: false),
                                    ),
                                    const SizedBox(height: 20),
                                    if (_error != null) ...[
                                      Text(
                                        _error!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: colorScheme.error),
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    FilledButton(
                                      onPressed: _isSaving ? null : _save,
                                      child: _isSaving
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Save'),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Failed to load profile',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Retry'),
            ),
          ],
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
