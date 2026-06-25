import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_header.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../feed/models/feed_post.dart';
import '../feed/models/post.dart';
import '../feed/repository/feed_repository.dart';
import '../feed/widgets/post_card.dart';
import 'controller/profile_controller.dart';
import 'models/user_profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({
    super.key,
    required this.userId,
    this.showTopHeader = true,
    this.showBackButton = true,
  });

  final String userId;
  final bool showTopHeader;
  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ProfilePage(
        userId: userId,
        showTopHeader: showTopHeader,
        showBackButton: showBackButton,
      ),
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({
    super.key,
    required this.userId,
    required this.showTopHeader,
    required this.showBackButton,
  });

  final String userId;
  final bool showTopHeader;
  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMeRoute = userId.trim().toLowerCase() == 'me';

    final resolvedUserIdAsync =
        isMeRoute ? ref.watch(currentUserIdProvider) : AsyncValue.data(userId);

    return resolvedUserIdAsync.when(
      loading: () => _ProfileLoadingView(
        showTopHeader: showTopHeader,
        showBackButton: showBackButton,
      ),
      error: (err, _) => _ProfileErrorScaffold(
        message: err.toString(),
        showTopHeader: showTopHeader,
        showBackButton: showBackButton,
        onRetry: () => ref.refresh(currentUserIdProvider),
      ),
      data: (resolvedUserId) {
        final id = (resolvedUserId ?? '').trim();
        if (id.isEmpty) {
          return _ProfileErrorScaffold(
            message: 'Not logged in.',
            showTopHeader: showTopHeader,
            showBackButton: showBackButton,
            onRetry: () => ref.refresh(currentUserIdProvider),
          );
        }

        final asyncState = ref.watch(profileControllerProvider(id));

        return asyncState.when(
          loading: () => _ProfileLoadingView(
            showTopHeader: showTopHeader,
            showBackButton: showBackButton,
          ),
          error: (err, _) {
            return _ProfileErrorScaffold(
              message: err.toString(),
              showTopHeader: showTopHeader,
              showBackButton: showBackButton,
              onRetry: () =>
                  ref.read(profileControllerProvider(id).notifier).refresh(),
            );
          },
          data: (state) {
            final meId = ref.watch(currentUserIdProvider).valueOrNull;
            final profileUserId = state.profile.id.trim().isEmpty
                ? state.userId
                : state.profile.id.trim();

            final profile = state.profile.copyWith(id: profileUserId);
            final isSelf = (meId != null && meId == profileUserId);

            return ProfileContent(
              user: profile,
              isSelf: isSelf,
              showTopHeader: showTopHeader,
              showBackButton: showBackButton,
            );
          },
        );
      },
    );
  }
}

class ProfileContent extends ConsumerStatefulWidget {
  const ProfileContent({
    super.key,
    required this.user,
    required this.isSelf,
    required this.showTopHeader,
    required this.showBackButton,
  });

  final UserProfile user;
  final bool isSelf;
  final bool showTopHeader;
  final bool showBackButton;

  @override
  ConsumerState<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<ProfileContent> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    // Unused
  }

  /// Called whenever the profile tab is activated (bottom-nav tap or switch).
  /// Jumps to the top immediately and refreshes the post/profile data.
  void _onTabActivated() {
    void execute() {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      ref
          .read(profileControllerProvider(widget.user.id).notifier)
          .refreshPostsFirstPage();
    }

    // If the CustomScrollView isn't laid out yet (first visit to this tab),
    // defer one frame so the scroll controller has clients.
    if (_scrollController.hasClients) {
      execute();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => execute());
    }
  }

  Future<void> _archivePost(String postId, String userId) async {
    final controller = ref.read(profileControllerProvider(userId).notifier);
    controller.updatePostArchived(postId, isArchived: true);
    try {
      final repo = FeedRepository(dio: ref.read(apiClientProvider).dio);
      await repo.archivePost(postId: postId);
    } catch (_) {
      controller.updatePostArchived(postId, isArchived: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to archive. Please try again.')),
      );
    }
  }

  Future<void> _unarchivePost(String postId, String userId) async {
    final controller = ref.read(profileControllerProvider(userId).notifier);
    controller.updatePostArchived(postId, isArchived: false);
    try {
      final repo = FeedRepository(dio: ref.read(apiClientProvider).dio);
      await repo.unarchivePost(postId: postId);
    } catch (_) {
      controller.updatePostArchived(postId, isArchived: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to unarchive. Please try again.')),
      );
    }
  }

  Future<void> _binPost(String postId, String userId) async {
    try {
      final repo = FeedRepository(dio: ref.read(apiClientProvider).dio);
      await repo.softDeletePost(postId: postId);
      ref.read(profileControllerProvider(userId).notifier).removePost(postId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to move to bin. Please try again.')),
      );
    }
  }

  Future<void> _editPost(Post post, String userId) async {
    final result = await context.push<Post?>('/post/create', extra: post);
    if (result != null && mounted) {
      ref.read(profileControllerProvider(userId).notifier).updatePost(result);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _openFollowingSheet(
    BuildContext context, {
    required String meUserId,
    required int initialFollowingCount,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _FollowingSheet(
          meUserId: meUserId,
          initialFollowingCount: initialFollowingCount,
          onFollowingCountChanged: (count) {
            ref
                .read(profileControllerProvider(meUserId).notifier)
                .setFollowingCount(count);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showTopHeader) {
      ref.listen<int>(profileScrollToTopProvider, (_, __) => _onTabActivated());
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final userId = widget.user.id;
    final isSelf = widget.isSelf;

    final posts = ref.watch(profileControllerProvider(userId)
        .select((v) => v.valueOrNull?.posts ?? const <Post>[]));

    final isLoadingMorePosts = ref.watch(profileControllerProvider(userId)
        .select((v) => v.valueOrNull?.isLoadingMorePosts ?? false));

    final postsHasMore = ref.watch(profileControllerProvider(userId)
        .select((v) => v.valueOrNull?.postsHasMore ?? false));

    final displayName = ref.watch(profileControllerProvider(userId)
        .select((v) => v.valueOrNull?.profile.displayName));

    Future<void> onRefresh() {
      return ref
          .read(profileControllerProvider(userId).notifier)
          .refreshPostsFirstPage();
    }

    void maybeFetchMore(ScrollMetrics metrics) {
      // If the list can't scroll yet, don't auto-paginate.
      if (metrics.maxScrollExtent <= 0) return;

      // Trigger slightly before the bottom for smoother pagination.
      const threshold = 320.0;
      if (metrics.extentAfter > threshold) return;

      if (!postsHasMore || isLoadingMorePosts) return;
      ref.read(profileControllerProvider(userId).notifier).fetchNextPosts();
    }

    Widget glassHeader() {
      final canPop = Navigator.of(context).canPop();

      return SliverAppBar(
        pinned: true,
        floating: false,
        automaticallyImplyLeading: false,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 44,
        titleSpacing: 0,
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        title: AppHeader(
          height: 44,
          title: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!_scrollController.hasClients) return;
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
            child: Text(
              'PaperStock',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          left: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showBackButton && canPop)
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
              const ThemeToggleButton(),
            ],
          ),
          right: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NotificationBellButton(),
              if (!isSelf) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Options',
                  onSelected: (value) {
                    if (value == 'report') {
                      _showReportUserDialog(context, ref, userId);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report Account'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget profileHeader() {
      return _ProfileHeader(
        userId: userId,
        isSelf: isSelf,
        displayName: widget.user.displayName,
        bio: widget.user.bio,
        followersCount: widget.user.followersCount,
        followingCount: widget.user.followingCount,
        isFollowing: widget.user.isFollowing,
        onEditProfile: isSelf ? () => context.push('/profile/edit') : null,
        onOpenSettings: isSelf ? () => context.push('/settings') : null,
        onOpenFollowing: isSelf
            ? () => _openFollowingSheet(
                  context,
                  meUserId: userId,
                  initialFollowingCount: widget.user.followingCount,
                )
            : null,
        onToggleFollow: isSelf
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(profileControllerProvider(userId).notifier)
                      .toggleFollow();
                } catch (_) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content:
                          Text('Failed to update follow. Please try again.'),
                    ),
                  );
                }
              },
      );
    }

    SliverList sliverPosts() {
      final list = posts;
      final isLoadingMore = isLoadingMorePosts;

      final int contentCount = list.length + (isLoadingMore ? 1 : 0);
      final int itemCount = contentCount == 0 ? 0 : (contentCount * 2 - 1);

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i.isOdd) return const SizedBox(height: 22);

            final index = i ~/ 2;

            if (isLoadingMore && index == list.length) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 24),
                    child: Center(
                      child: SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                ),
              );
            }

            final post = list[index];

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RepaintBoundary(
                  child: PostCard(
                    key: ValueKey<String>(post.id),
                    post: _toFeedPost(
                      post,
                      authorName: displayName,
                    ),
                    isLiked: post.isLiked,
                    isBookmarked: post.isBookmarked,
                    onLike: null,
                    onBookmark: null,
                    onArchive: (isSelf && !post.isArchived)
                        ? () => _archivePost(post.id, userId)
                        : null,
                    onUnarchive: (isSelf && post.isArchived)
                        ? () => _unarchivePost(post.id, userId)
                        : null,
                    onBin: isSelf ? () => _binPost(post.id, userId) : null,
                    onEdit: isSelf ? () => _editPost(post, userId) : null,
                  ),
                ),
              ),
            );
          },
          childCount: itemCount,
        ),
      );
    }

    Widget emptyState() {
      const label = 'No posts yet.';
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 28),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    Widget buildInnerCustomScrollView() {
      final isEmptyList = posts.isEmpty && !isLoadingMorePosts;

      return CustomScrollView(
        key: const PageStorageKey<String>('posts'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          if (isEmptyList)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: emptyState(),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 98),
              sliver: sliverPosts(),
            ),
        ],
      );
    }

    final double topPadding = MediaQuery.paddingOf(context).top;
    final double appBarHeight =
        widget.showTopHeader ? (44.0 + topPadding) : 0.0;

    return RefreshIndicator(
      edgeOffset: appBarHeight,
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              notification is OverscrollNotification) {
            maybeFetchMore(notification.metrics);
          }
          return false;
        },
        child: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return <Widget>[
              if (widget.showTopHeader) glassHeader(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.showTopHeader ? 100.0 : 24.0,
                  24,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: profileHeader(),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: buildInnerCustomScrollView(),
        ),
      ),
    );
  }
}

class _ProfileLoadingView extends StatelessWidget {
  const _ProfileLoadingView({
    required this.showTopHeader,
    required this.showBackButton,
  });

  final bool showTopHeader;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        if (showTopHeader)
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            toolbarHeight: 44,
            titleSpacing: 0,
            shape: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            title: AppHeader(
              height: 44,
              title: Text(
                'PaperStock',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              left: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBackButton && Navigator.of(context).canPop())
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                  const ThemeToggleButton(),
                ],
              ),
              right: const NotificationBellButton(),
            ),
          ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileErrorScaffold extends StatelessWidget {
  const _ProfileErrorScaffold({
    required this.message,
    required this.showTopHeader,
    required this.showBackButton,
    required this.onRetry,
  });

  final String message;
  final bool showTopHeader;
  final bool showBackButton;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        if (showTopHeader)
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            toolbarHeight: 44,
            titleSpacing: 0,
            shape: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
            title: AppHeader(
              height: 44,
              title: Text(
                'PaperStock',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              left: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBackButton && Navigator.of(context).canPop())
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                  const ThemeToggleButton(),
                ],
              ),
              right: const NotificationBellButton(),
            ),
          ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Failed to load profile',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.userId,
    required this.isSelf,
    required this.displayName,
    required this.bio,
    required this.followersCount,
    required this.followingCount,
    required this.isFollowing,
    required this.onEditProfile,
    required this.onOpenSettings,
    required this.onOpenFollowing,
    required this.onToggleFollow,
  });

  final String userId;
  final bool isSelf;
  final String? displayName;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final VoidCallback? onEditProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenFollowing;
  final VoidCallback? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final name = (displayName ?? '').trim();

    final display = name.isEmpty ? 'User ${_shortId(userId)}' : name;

    final nameStyle = GoogleFonts.lora(
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.08,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: 24),
            Text(
              display,
              style: nameStyle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              (bio ?? '').trim().isEmpty ? 'No bio yet.' : (bio ?? '').trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _StatTile(label: 'Followers', value: followersCount),
            const SizedBox(width: 52),
            _StatTile(
              label: 'Following',
              value: followingCount,
              onTap: onOpenFollowing,
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (isSelf)
          LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 520;
              if (isNarrow) {
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        onPressed: onEditProfile,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Edit Profile'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onOpenSettings,
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Settings'),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 220,
                    child: FilledButton(
                      onPressed: onEditProfile,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton(
                      onPressed: onOpenSettings,
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Settings'),
                    ),
                  ),
                ],
              );
            },
          )
        else
          Center(
            child: SizedBox(
              width: 240,
              child: FilledButton(
                onPressed: onToggleFollow,
                child: Text(isFollowing ? 'Following' : 'Follow'),
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              value.toString(),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowListItem {
  const _FollowListItem({
    required this.id,
    required this.displayName,
    required this.isFollowing,
  });

  final String id;
  final String displayName;
  final bool isFollowing;

  _FollowListItem copyWith({
    String? displayName,
    bool? isFollowing,
  }) {
    return _FollowListItem(
      id: id,
      displayName: displayName ?? this.displayName,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}

class _FollowingSheet extends ConsumerStatefulWidget {
  const _FollowingSheet({
    required this.meUserId,
    required this.initialFollowingCount,
    required this.onFollowingCountChanged,
  });

  final String meUserId;
  final int initialFollowingCount;
  final ValueChanged<int> onFollowingCountChanged;

  @override
  ConsumerState<_FollowingSheet> createState() => _FollowingSheetState();
}

class _FollowingSheetState extends ConsumerState<_FollowingSheet> {
  static const _debounceDuration = Duration(milliseconds: 400);

  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loadingFollowing = true;
  bool _loadingSearch = false;
  String? _error;

  late int _followingCount;

  List<_FollowListItem> _following = const <_FollowListItem>[];
  List<_FollowListItem> _results = const <_FollowListItem>[];

  final Set<String> _inFlight = <String>{};

  Dio get _dio => ref.read(apiClientProvider).dio;

  @override
  void initState() {
    super.initState();
    _followingCount = widget.initialFollowingCount;
    _searchController.addListener(_onQueryChanged);
    unawaited(_loadFollowing());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      unawaited(_runSearch(_searchController.text));
    });
  }

  Future<void> _loadFollowing() async {
    setState(() {
      _loadingFollowing = true;
      _error = null;
    });

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/users/${widget.meUserId}/following',
        queryParameters: const <String, dynamic>{
          'limit': 50,
        },
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};

      final itemsJson =
          (data['items'] is List) ? (data['items'] as List) : const <dynamic>[];

      final items = itemsJson
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final id = (e['id'] as Object?)?.toString() ?? '';
            final name = (e['display_name'] as Object?)?.toString() ?? '';
            return _FollowListItem(
              id: id,
              displayName: name.trim().isEmpty ? 'Unknown' : name.trim(),
              isFollowing: true,
            );
          })
          .where((u) => u.id.trim().isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _following = items;
        _loadingFollowing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFollowing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runSearch(String rawQuery) async {
    final q = rawQuery.trim();

    if (q.isEmpty) {
      setState(() {
        _loadingSearch = false;
        _error = null;
        _results = const <_FollowListItem>[];
      });
      return;
    }

    setState(() {
      _loadingSearch = true;
      _error = null;
    });

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/search',
        queryParameters: <String, dynamic>{
          'type': 'users',
          'q': q,
        },
      );

      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>)
          : const <String, dynamic>{};

      final itemsJson =
          (data['items'] is List) ? (data['items'] as List) : const <dynamic>[];

      final items = itemsJson
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final id = (e['id'] as Object?)?.toString() ?? '';
            final name = (e['display_name'] as Object?)?.toString() ?? '';
            final isFollowing = e['is_following'] == true;

            return _FollowListItem(
              id: id,
              displayName: name.trim().isEmpty ? 'Unknown' : name.trim(),
              isFollowing: isFollowing,
            );
          })
          .where((u) => u.id.trim().isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _results = items;
        _loadingSearch = false;
        _error = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _results = const <_FollowListItem>[];
        _error = e.response?.data?.toString() ?? e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _results = const <_FollowListItem>[];
        _error = e.toString();
      });
    }
  }

  void _setFollowState(String userId, bool isFollowing) {
    _following = _following
        .where((u) => u.id != userId || isFollowing)
        .toList(growable: false);

    _results = _results
        .map((u) => u.id == userId ? u.copyWith(isFollowing: isFollowing) : u)
        .toList(growable: false);
  }

  void _addToFollowingIfMissing(_FollowListItem item) {
    if (_following.any((u) => u.id == item.id)) return;
    _following = <_FollowListItem>[
      item.copyWith(isFollowing: true),
      ..._following
    ];
  }

  void _applyFollowingCountDelta(int delta) {
    _followingCount = (_followingCount + delta).clamp(0, 1 << 30);
    widget.onFollowingCountChanged(_followingCount);
  }

  Future<void> _toggleFollow(_FollowListItem user) async {
    final id = user.id.trim();
    if (id.isEmpty) return;
    if (id == widget.meUserId) return;
    if (id == widget.meUserId) return;
    if (_inFlight.contains(id)) return;

    final repo = ref.read(profileRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    final beforeFollowing = user.isFollowing;
    final nextFollowing = !beforeFollowing;

    setState(() {
      _inFlight.add(id);

      if (nextFollowing) {
        _addToFollowingIfMissing(user);
      } else {
        _following =
            _following.where((u) => u.id != id).toList(growable: false);
      }

      _setFollowState(id, nextFollowing);
      _applyFollowingCountDelta(nextFollowing ? 1 : -1);
    });

    try {
      if (nextFollowing) {
        await repo.follow(userId: id);
      } else {
        await repo.unfollow(userId: id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (beforeFollowing) {
          _addToFollowingIfMissing(user.copyWith(isFollowing: true));
        } else {
          _following =
              _following.where((u) => u.id != id).toList(growable: false);
        }

        _setFollowState(id, beforeFollowing);
        _applyFollowingCountDelta(beforeFollowing ? 1 : -1);
        _inFlight.remove(id);
      });

      messenger.showSnackBar(
        const SnackBar(
            content: Text('Failed to update follow. Please try again.')),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _inFlight.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchController.text.trim();

    final showingSearch = query.isNotEmpty;
    final list = showingSearch ? _results : _following;
    final isLoading = showingSearch ? _loadingSearch : _loadingFollowing;

    Widget header() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Following',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search users',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    Widget emptyView() {
      final label = showingSearch ? 'No results.' : 'Not following anyone yet.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    Widget errorView() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Something went wrong.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget listView(ScrollController controller) {
      if (_error != null) return errorView();

      if (isLoading) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        );
      }

      if (list.isEmpty) return emptyView();

      return ListView.separated(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          final user = list[index];
          final isMe = user.id == widget.meUserId;
          final inFlight = _inFlight.contains(user.id);

          final buttonLabel = user.isFollowing ? 'Following' : 'Follow';

          final button = isMe
              ? const SizedBox.shrink()
              : (user.isFollowing
                  ? OutlinedButton(
                      onPressed: inFlight ? null : () => _toggleFollow(user),
                      child: Text(buttonLabel),
                    )
                  : FilledButton(
                      onPressed: inFlight ? null : () => _toggleFollow(user),
                      child: Text(buttonLabel),
                    ));

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/profile/${user.id}'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        user.displayName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    button,
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Material(
            color: theme.scaffoldBackgroundColor,
            child: Column(
              children: <Widget>[
                header(),
                Expanded(child: listView(controller)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

FeedPost _toFeedPost(Post post, {required String? authorName}) {
  // Prefer the explicit override (e.g. profile owner's display name), then
  // fall back to the name returned by the API, then 'Unknown'.
  final overridden = (authorName ?? '').trim();
  final fromApi = post.authorName.trim();
  final resolvedAuthor = overridden.isNotEmpty
      ? overridden
      : (fromApi.isNotEmpty ? fromApi : 'Unknown');

  return FeedPost(
    id: post.id,
    title: post.title,
    bodyPreview: post.body,
    tags: post.tags,
    authorId: post.authorId,
    authorName: resolvedAuthor,
    readTimeMinutes: post.readTimeMinutes,
    likesCount: post.likesCount,
    isArchived: post.isArchived,
    isNsfw: post.isNsfw,
    moderationStatus: post.moderationStatus,
    moderationNote: post.moderationNote,
    rejectedAt: post.rejectedAt,
    canEditAfterRejection: post.canEditAfterRejection,
  );
}

String _shortId(String id) {
  if (id.length <= 8) return id;
  return id.substring(0, 8);
}

// ─── Account Reporting Dialogs ────────────────────────────────────────────────

void _showReportUserDialog(BuildContext context, WidgetRef ref, String targetUserId) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Account',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? cardCharcoalText : cardCreamText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Why are you reporting this account?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                ),
              ),
              const SizedBox(height: 20),
              _UserReportOption(
                label: 'Spam',
                onTap: () => _submitUserReport(context, ref, targetUserId, 'spam'),
                isDark: isDark,
              ),
              _UserReportOption(
                label: 'Abuse or Harassment',
                onTap: () => _submitUserReport(context, ref, targetUserId, 'abuse'),
                isDark: isDark,
              ),
              _UserReportOption(
                label: 'Other',
                onTap: () async {
                  Navigator.pop(context); // close bottom sheet
                  final customReason = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        backgroundColor: isDark ? cardCharcoalDark : cardCreamLight,
                        title: Text(
                          'Specify Reason',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                        ),
                        content: TextField(
                          controller: controller,
                          maxLength: 200,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            color: isDark ? cardCharcoalText : cardCreamText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter reason (up to 200 characters)...',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? cardCharcoalText : cardCreamText,
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'CANCEL',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final text = controller.text.trim();
                              if (text.isNotEmpty) {
                                Navigator.pop(context, text);
                              }
                            },
                            child: Text(
                              'SUBMIT',
                              style: GoogleFonts.inter(
                                color: isDark ? cardCharcoalText : cardCreamText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                  if (customReason != null && customReason.isNotEmpty) {
                    if (context.mounted) {
                      _submitUserReport(context, ref, targetUserId, customReason, popContext: false);
                    }
                  }
                },
                isDark: isDark,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _UserReportOption extends StatelessWidget {
  const _UserReportOption({
    required this.label,
    required this.onTap,
    required this.isDark,
  });
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? cardCharcoalText : cardCreamText;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? cardCharcoalEdge : cardCreamEdge,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? cardCharcoalSubtext : cardCreamSubtext,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _submitUserReport(
  BuildContext context,
  WidgetRef ref,
  String targetUserId,
  String reason, {
  bool popContext = true,
}) async {
  if (popContext) {
    Navigator.pop(context); // close bottom sheet
  }

  final dio = ref.read(apiClientProvider).dio;
  try {
    await dio.post<void>(
      '/api/v1/users/$targetUserId/report',
      data: <String, dynamic>{'reason': reason},
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you. The account has been reported for review.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } on DioException catch (e) {
    if (!context.mounted) return;
    final msg = e.response?.data?['detail']?.toString() ?? 'Failed to submit report';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
