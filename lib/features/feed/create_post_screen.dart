import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/widgets/notification_bell_button.dart';
import 'controller/feed_controller.dart';
import 'models/post.dart';

class CreatePostDraft {
  const CreatePostDraft({
    required this.title,
    required this.body,
    required this.tags,
    required this.postType,
    required this.storyType,
    this.parentId,
    this.isNsfw = false,
  });

  final String title;
  final String body;
  final List<String> tags;
  final PostType postType;
  final StoryType? storyType;
  final String? parentId;
  final bool isNsfw;
}

enum PostType {
  story('story');

  const PostType(this.apiValue);

  final String apiValue;
}

enum StoryType {
  fictional('fictional'),
  real('real');

  const StoryType(this.apiValue);

  final String apiValue;
}

class _CreatePostSubmitState {
  const _CreatePostSubmitState({
    required this.isSubmitting,
    required this.uiMessage,
    required this.uiMessageNonce,
  });

  final bool isSubmitting;
  final String? uiMessage;
  final int uiMessageNonce;

  _CreatePostSubmitState copyWith({
    bool? isSubmitting,
    String? uiMessage,
    int? uiMessageNonce,
  }) {
    return _CreatePostSubmitState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      uiMessage: uiMessage,
      uiMessageNonce: uiMessageNonce ?? this.uiMessageNonce,
    );
  }

  static const idle = _CreatePostSubmitState(
    isSubmitting: false,
    uiMessage: null,
    uiMessageNonce: 0,
  );
}

final _createPostControllerProvider =
    AutoDisposeNotifierProvider<_CreatePostController, _CreatePostSubmitState>(
  _CreatePostController.new,
);

final _trendingTagsProvider =
    AutoDisposeFutureProvider<List<String>>((ref) async {
  final dio = ref.watch(apiClientProvider).dio;
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '/api/v1/search/trending-tags',
    );
    final body = response.data ?? const <String, dynamic>{};
    final data =
        (body['data'] is List) ? (body['data'] as List) : const <dynamic>[];
    return data
        .map((e) {
          final s = e.toString().trim();
          final noHash = s.startsWith('#') ? s.substring(1) : s;
          return noHash.trim().toLowerCase();
        })
        .where((e) => e.isNotEmpty)
        .take(5)
        .toList(growable: false);
  } catch (_) {
    return const <String>[];
  }
});

class _CreatePostController
    extends AutoDisposeNotifier<_CreatePostSubmitState> {
  @override
  _CreatePostSubmitState build() => _CreatePostSubmitState.idle;

  Future<Post?> submit(CreatePostDraft draft, {String? editPostId}) async {
    if (state.isSubmitting) return null;

    state = state.copyWith(isSubmitting: true);

    try {
      final repo = ref.read(feedRepositoryProvider);
      final Post result;
      if (editPostId != null) {
        result = await repo.updatePost(
          postId: editPostId,
          title: draft.title,
          body: draft.body,
          tags: draft.tags,
          postType: draft.postType.apiValue,
          storyType: draft.storyType?.apiValue,
          isNsfw: draft.isNsfw,
        );
      } else {
        result = await repo.createPost(
          title: draft.title,
          body: draft.body,
          tags: draft.tags,
          postType: draft.postType.apiValue,
          storyType: draft.storyType?.apiValue,
          parentId: draft.parentId,
          isNsfw: draft.isNsfw,
        );
      }

      state = state.copyWith(
        isSubmitting: false,
        uiMessage: null,
      );
      return result;
    } on DioException catch (e) {
      final serverMessage = _extractServerError(e) ?? '';
      final msgLower = serverMessage.toLowerCase();

      if (msgLower.contains('already have a post with this title') ||
          msgLower.contains('title already exists')) {
        state = state.copyWith(
          isSubmitting: false,
          uiMessage:
              'You already have a post with this title. Please choose a different title.',
          uiMessageNonce: state.uiMessageNonce + 1,
        );
        return null;
      }

      final actionWord = editPostId != null ? 'update' : 'create';
      state = state.copyWith(
        isSubmitting: false,
        uiMessage: 'Failed to $actionWord post. Please try again.',
        uiMessageNonce: state.uiMessageNonce + 1,
      );
      return null;
    } catch (_) {
      final actionWord = editPostId != null ? 'update' : 'create';
      state = state.copyWith(
        isSubmitting: false,
        uiMessage: 'Failed to $actionWord post. Please try again.',
        uiMessageNonce: state.uiMessageNonce + 1,
      );
      return null;
    }
  }

  void consumeUiMessage() {
    if (state.uiMessage == null) return;
    state = state.copyWith(uiMessage: null);
  }

  String? _extractServerError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail']?.toString();
      if (detail != null && detail.trim().isNotEmpty) return detail;
      final error = data['error']?.toString();
      if (error != null && error.trim().isNotEmpty) return error;
    }
    return e.message;
  }
}

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.postToEdit});

  final Post? postToEdit;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagController = TextEditingController();

  StoryType? _storyType = StoryType.real;
  bool _isNsfw = false;

  final List<String> _tags = <String>[];
  String? _tagsError;
  String? _metaError;

  List<Post> _myPreviousPosts = [];
  String? _selectedParentId;
  bool _isLoadingMyPosts = true;

  @override
  void initState() {
    super.initState();
    if (widget.postToEdit != null) {
      _titleController.text = widget.postToEdit!.title;
      _bodyController.text = widget.postToEdit!.body;
      _tags.addAll(widget.postToEdit!.tags);
      _isNsfw = widget.postToEdit!.isNsfw;
      if (widget.postToEdit!.storyType != null) {
        _storyType = StoryType.values.firstWhere(
          (e) => e.apiValue == widget.postToEdit!.storyType,
          orElse: () => StoryType.real,
        );
      }
      _isLoadingMyPosts = false;
    } else {
      _loadMyPreviousPosts();
    }
  }

  Future<void> _loadMyPreviousPosts() async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final meResponse =
          await dio.get<Map<String, dynamic>>('/api/v1/users/me');
      final meBody = meResponse.data ?? const <String, dynamic>{};
      final meData = (meBody['data'] is Map<String, dynamic>)
          ? (meBody['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};
      final myId = meData['id']?.toString();

      if (myId != null && myId.isNotEmpty) {
        final postsResponse = await dio.get<Map<String, dynamic>>(
          '/api/v1/users/$myId/posts',
          queryParameters: <String, dynamic>{'limit': 50},
        );
        final postsBody = postsResponse.data ?? const <String, dynamic>{};
        final postsData = (postsBody['data'] is Map<String, dynamic>)
            ? (postsBody['data'] as Map<String, dynamic>)
            : const <String, dynamic>{};
        final itemsJson = (postsData['items'] is List)
            ? (postsData['items'] as List)
            : const <dynamic>[];

        final posts = itemsJson
            .whereType<Map<String, dynamic>>()
            .map(Post.fromJson)
            .toList();

        if (mounted) {
          setState(() {
            _myPreviousPosts = posts;
            _isLoadingMyPosts = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingMyPosts = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMyPosts = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTagsFromInput() {
    final raw = _tagController.text;
    final next = _normalizeTags(raw);
    if (next.isEmpty) return;

    setState(() {
      _tagsError = null;

      for (final t in next) {
        if (_tags.length >= 5) {
          _tagsError = 'Up to 5 tags allowed';
          break;
        }
        if (_tags.contains(t)) continue;
        if (t.length > 20) {
          _tagsError = 'Tags must be 20 characters or less';
          continue;
        }
        _tags.add(t);
      }

      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      _tagsError = null;
    });
  }

  void _addTrendingTag(String tag) {
    if (_tags.contains(tag)) return;
    if (_tags.length >= 5) {
      setState(() => _tagsError = 'Up to 5 tags allowed');
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagsError = null;
    });
  }

  void _validateTags() {
    setState(() {
      if (_tags.isEmpty) {
        _tagsError = 'Add at least 1 tag';
      } else {
        _tagsError = null;
      }
    });
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null) return;

    _addTagsFromInput();
    final ok = form.validate();
    _validateTags();

    if (!ok) return;
    if (_tags.isEmpty) return;

    if (_storyType == null) {
      setState(() => _metaError = 'Pick fictional or real');
      return;
    }

    FocusScope.of(context).unfocus();

    final draft = CreatePostDraft(
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      tags: List<String>.of(_tags),
      postType: PostType.story,
      storyType: _storyType,
      parentId: _selectedParentId,
      isNsfw: _isNsfw,
    );

    final created = await ref
        .read(_createPostControllerProvider.notifier)
        .submit(draft, editPostId: widget.postToEdit?.id);
    if (!mounted) return;
    if (created != null) {
      context.pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fieldFillColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.05,
    );

    ref.listen(_createPostControllerProvider, (prev, next) {
      final prevNonce = prev?.uiMessageNonce ?? 0;
      if (next.uiMessageNonce == prevNonce) return;
      final message = next.uiMessage;
      if (message == null || message.trim().isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(_createPostControllerProvider.notifier).consumeUiMessage();
      });
    });

    final submitState = ref.watch(_createPostControllerProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        title: Text(
          'PaperStock',
          style: GoogleFonts.playfairDisplay(
              fontSize: 20, fontWeight: FontWeight.w700),
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
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.postToEdit != null ? 'Edit Post' : 'Create Post',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      // Rejection warning banner
                      if (widget.postToEdit != null &&
                          widget.postToEdit!.moderationStatus == 'rejected') ...[
                        const SizedBox(height: 12),
                        _RejectionWarningBanner(post: widget.postToEdit!),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Title',
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return 'Title is required';
                          return null;
                        },
                      ),
                      // ── Sequel / Chaining Dropdown ───────────────────────────
                      if (widget.postToEdit == null &&
                          !_isLoadingMyPosts &&
                          _myPreviousPosts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedParentId,
                          decoration: InputDecoration(
                            labelText: 'Is this a sequel / next part?',
                            filled: true,
                            fillColor: fieldFillColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.link_rounded),
                          ),
                          dropdownColor: isDark ? softBlack : Colors.white,
                          style: TextStyle(color: colorScheme.onSurface),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Start a New Story (Part 1)'),
                            ),
                            ..._myPreviousPosts
                                .where((p) =>
                                    p.nextPostId == null ||
                                    p.nextPostId!.isEmpty)
                                .map(
                                  (p) => DropdownMenuItem<String>(
                                    value: p.id,
                                    child: Text(
                                      p.title,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedParentId = val;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bodyController,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Body',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        maxLines: null,
                        minLines: 12,
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return 'Body is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            ChoiceChip(
                              label: const Text('Fictional'),
                              selected: _storyType == StoryType.fictional,
                              selectedColor:
                                  colorScheme.primary.withValues(alpha: 0.20),
                              backgroundColor: isDark ? softBlack : null,
                              side: isDark
                                  ? const BorderSide(color: borderBlack)
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              labelStyle:
                                  TextStyle(color: colorScheme.onSurface),
                              onSelected: (_) {
                                setState(() {
                                  _storyType = StoryType.fictional;
                                  _metaError = null;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Real'),
                              selected: _storyType == StoryType.real,
                              selectedColor:
                                  colorScheme.primary.withValues(alpha: 0.20),
                              backgroundColor: isDark ? softBlack : null,
                              side: isDark
                                  ? const BorderSide(color: borderBlack)
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              labelStyle:
                                  TextStyle(color: colorScheme.onSurface),
                              onSelected: (_) {
                                setState(() {
                                  _storyType = StoryType.real;
                                  _metaError = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_metaError != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          _metaError!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // NSFW Checkbox
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: fieldFillColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            Checkbox(
                              value: _isNsfw,
                              onChanged: (value) {
                                setState(() {
                                  _isNsfw = value ?? false;
                                });
                              },
                              activeColor: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Not Safe For Work (NSFW)',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.info_outline,
                                size: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              tooltip: 'NSFW content includes mature themes, violence, or explicit material. Posts marked as NSFW will be blurred and require age confirmation to view.',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('About NSFW'),
                                    content: const Text(
                                      'NSFW (Not Safe For Work) content includes mature themes, violence, explicit material, or content that may not be appropriate for all audiences.\n\nPosts marked as NSFW will be shown with a blur overlay and require users to confirm they are 18+ before viewing.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('Got it'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_tags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tags
                              .map(
                                (t) => InputChip(
                                  label: Text('#$t'),
                                  backgroundColor: isDark ? softBlack : null,
                                  side: isDark
                                      ? const BorderSide(color: borderBlack)
                                      : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  labelStyle: isDark
                                      ? theme.textTheme.labelMedium?.copyWith(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                        )
                                      : null,
                                  onDeleted: () => _removeTag(t),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _tagController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addTagsFromInput(),
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Tags',
                          helperText: 'Add 1–5 tags (max 20 chars each)',
                          errorText: _tagsError,
                          filled: true,
                          fillColor: fieldFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            onPressed: _addTagsFromInput,
                            icon: const Icon(Icons.add),
                            tooltip: 'Add tag',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_tags.length}/5',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // ── Trending tags ──────────────────────────────────────
                      Builder(builder: (context) {
                        final async = ref.watch(_trendingTagsProvider);
                        return async.maybeWhen(
                          data: (tags) {
                            if (tags.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const SizedBox(height: 14),
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.local_fire_department_outlined,
                                      size: 15,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Trending',
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: tags.map((tag) {
                                    final isSelected = _tags.contains(tag);
                                    return FilterChip(
                                      label: Text('#$tag'),
                                      selected: isSelected,
                                      selectedColor: colorScheme.primary
                                          .withValues(alpha: 0.20),
                                      backgroundColor:
                                          isDark ? softBlack : null,
                                      side: isDark
                                          ? const BorderSide(color: borderBlack)
                                          : null,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      labelStyle: TextStyle(
                                        color: colorScheme.onSurface,
                                      ),
                                      onSelected: submitState.isSubmitting
                                          ? null
                                          : (_) {
                                              if (isSelected) {
                                                _removeTag(tag);
                                              } else {
                                                _addTrendingTag(tag);
                                              }
                                            },
                                    );
                                  }).toList(growable: false),
                                ),
                              ],
                            );
                          },
                          orElse: () => const SizedBox.shrink(),
                        );
                      }),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: submitState.isSubmitting
                            ? null
                            : _submit,
                        child: submitState.isSubmitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.postToEdit != null 
                                    ? (widget.postToEdit!.moderationStatus == 'rejected' 
                                        ? 'Repost for Review' 
                                        : 'Save')
                                    : 'Post',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _normalizeTags(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const <String>[];

  final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty);

  final result = <String>[];
  for (final p in parts) {
    final t = p.startsWith('#') ? p.substring(1) : p;
    final normalized = t.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    if (!result.contains(normalized)) {
      result.add(normalized);
    }
  }

  return result;
}

class _RejectionWarningBanner extends StatelessWidget {
  const _RejectionWarningBanner({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Calculate deletion time
    final rejectedAt = post.rejectedAt;
    if (rejectedAt == null) return const SizedBox.shrink();

    // 7 days for editable, 30 minutes for non-editable
    final deletionTime = post.canEditAfterRejection
        ? rejectedAt.add(const Duration(days: 7))
        : rejectedAt.add(const Duration(minutes: 30));
    final now = DateTime.now();
    final remaining = deletionTime.difference(now);

    // Format countdown
    String countdownText;
    if (remaining.isNegative) {
      countdownText = 'This post will be deleted soon';
    } else if (remaining.inDays > 0) {
      final hours = remaining.inHours % 24;
      countdownText = '${remaining.inDays}d ${hours}h remaining';
    } else if (remaining.inHours > 0) {
      final minutes = remaining.inMinutes % 60;
      countdownText = '${remaining.inHours}h ${minutes}m remaining';
    } else {
      countdownText = '${remaining.inMinutes}m remaining';
    }

    final canEdit = post.canEditAfterRejection;
    final color = canEdit ? Colors.orange[900] : Colors.red[900];
    final bgColor = canEdit ? Colors.orange[50] : Colors.red[50];
    final bgColorDark = canEdit 
        ? Colors.orange.withValues(alpha: 0.15)
        : Colors.red.withValues(alpha: 0.15);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? bgColorDark : bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (canEdit ? Colors.orange : Colors.red).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                canEdit ? Icons.edit_outlined : Icons.warning_amber_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canEdit 
                      ? 'Post Rejected - Edit to Resubmit'
                      : 'Post Rejected - Will Be Deleted',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (post.moderationNote != null && post.moderationNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${post.moderationNote}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                countdownText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'You can edit',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            Text(
              'Fix the issues and click "Repost for Review" to resubmit to moderators.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color?.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

