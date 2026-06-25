import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/card_brightness_provider.dart';
import '../../core/widgets/app_header.dart';
import '../../core/widgets/notification_bell_button.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../profile/controller/profile_controller.dart';
import '../profile/my_profile_screen.dart';
import '../swipe/swipe_screen.dart';
import '../qotd/qotd_screen.dart';
import 'controller/feed_controller.dart';
import 'models/post.dart';
import '../swipe/swipe_controller.dart';
import '../../core/storage/last_reading_store.dart';

const _kFeedMaxWidth = 720.0;
const _kDesktopSidebarWidth = 192.0;
const _kDesktopSidebarFeedGap = 28.0;
const _kDesktopContentMaxWidth =
    _kDesktopSidebarWidth + _kDesktopSidebarFeedGap + _kFeedMaxWidth;

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  int _previousIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentIndex = ref.watch(bottomNavIndexProvider);

    void onSelectBottomNav(int value) {
      if (value == 3) {
        ref.read(profileScrollToTopProvider.notifier).state++;
      }
      if (value == currentIndex) return;
      setState(() {
        _previousIndex = currentIndex;
      });
      ref.read(bottomNavIndexProvider.notifier).state = value;
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    final pages = <Widget>[
      const KeyedSubtree(
        key: ValueKey('tab-discover'),
        child: SwipeDeckContent(),
      ),
      const KeyedSubtree(
        key: ValueKey('tab-daily'),
        child: QotdScreen(),
      ),
      const KeyedSubtree(
        key: ValueKey('tab-bookmarks'),
        child: _BookmarksTab(),
      ),
      const KeyedSubtree(
        key: ValueKey('tab-profile'),
        child: MyProfileScreen(),
      ),
    ];

    final isMovingRight = currentIndex > _previousIndex;
    final mainContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
        final currentKey = pages[currentIndex].key;
        final isIncoming = child.key == currentKey;
        
        final double beginX;
        if (isIncoming) {
          beginX = isMovingRight ? 1.0 : -1.0;
        } else {
          beginX = isMovingRight ? -1.0 : 1.0;
        }

        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(beginX, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: pages[currentIndex],
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      extendBody: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width < 600;
          final isTablet = width >= 600 && width <= 1024;
          final isDesktop = width > 1024;

          Future<void> createPost() async {
            final result = await context.push<dynamic>('/post/create');
            if (result is Post) {
              // Resolve the logged-in user's real ID so we can update the right
              // profile controller instance.
              final meId = await ref.read(currentUserIdProvider.future);
              if (meId == null || !context.mounted) return;
              
              // Insert the post at the top locally first for immediate visual feedback
              ref
                  .read(profileControllerProvider(meId).notifier)
                  .insertPostAtTop(result);

              // Refresh the first page of posts and profile stats from the server
              ref
                  .read(profileControllerProvider(meId).notifier)
                  .refreshPostsFirstPage();
            }
          }

          Widget mainForSize() {
            if (isMobile) return mainContent;
            if (isTablet) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kFeedMaxWidth),
                  child: mainContent,
                ),
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kDesktopContentMaxWidth),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: _kDesktopSidebarWidth,
                      child: _DesktopSidebar(
                        selectedIndex: currentIndex,
                        onSelected: onSelectBottomNav,
                      ),
                    ),
                    const SizedBox(width: _kDesktopSidebarFeedGap),
                    SizedBox(width: _kFeedMaxWidth, child: mainContent),
                  ],
                ),
              ),
            );
          }

          final double rightInset = isMobile
              ? 16
              : (width -
                          (isDesktop
                              ? _kDesktopContentMaxWidth
                              : _kFeedMaxWidth)) /
                      2 +
                  16;

          final double bottomInset = isDesktop ? 24 : 88;

          return NestedScrollView(
            physics: (currentIndex == 0 || currentIndex == 1) ? const NeverScrollableScrollPhysics() : null,
            floatHeaderSlivers: false,
            headerSliverBuilder: (context, _) {
              return <Widget>[
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  automaticallyImplyLeading: false,
                  backgroundColor: colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
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
                    left: const ThemeToggleButton(),
                    title: Text(
                      'PaperStock',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    right: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (currentIndex == 0) const SwipeUndoButton(),
                        const NotificationBellButton(),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: Stack(
              children: <Widget>[
                mainForSize(),
                if (currentIndex == 3)
                  Positioned(
                    right: rightInset,
                    bottom: bottomInset,
                    child: FloatingActionButton(
                      onPressed: createPost,
                      tooltip: 'Create post',
                      child: const Icon(Icons.edit),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 1024;
          if (isDesktop) return const SizedBox.shrink();

          final theme = Theme.of(context);
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? coverMid
                      : cardCreamMid,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark
                        ? pageEdge
                        : cardCreamEdge,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.35 : 0.08,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: <Widget>[
                    _NavItem(
                      icon: Icons.description_outlined,
                      activeIcon: Icons.description,
                      label: 'Discover',
                      selected: currentIndex == 0,
                      onTap: () => onSelectBottomNav(0),
                    ),
                    _NavItem(
                      icon: Icons.wb_sunny_outlined,
                      activeIcon: Icons.wb_sunny,
                      label: 'Daily',
                      selected: currentIndex == 1,
                      onTap: () => onSelectBottomNav(1),
                    ),
                    _NavItem(
                      icon: Icons.bookmark_border,
                      activeIcon: Icons.bookmark,
                      label: 'Bookmarks',
                      selected: currentIndex == 2,
                      onTap: () => onSelectBottomNav(2),
                    ),
                    _NavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: 'Profile',
                      selected: currentIndex == 3,
                      onTap: () => onSelectBottomNav(3),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Desktop sidebar ──────────────────────────────────────────────────────────

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SidebarItem(
            isActive: selectedIndex == 0,
            icon: Icons.description_outlined,
            activeIcon: Icons.description,
            label: 'Discover',
            onTap: () => onSelected(0),
          ),
          const SizedBox(height: 8),
          _SidebarItem(
            isActive: selectedIndex == 1,
            icon: Icons.wb_sunny_outlined,
            activeIcon: Icons.wb_sunny,
            label: 'Daily',
            onTap: () => onSelected(1),
          ),
          const SizedBox(height: 8),
          _SidebarItem(
            isActive: selectedIndex == 2,
            icon: Icons.bookmark_border,
            activeIcon: Icons.bookmark,
            label: 'Bookmarks',
            onTap: () => onSelected(2),
          ),
          const SizedBox(height: 8),
          _SidebarItem(
            isActive: selectedIndex == 3,
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Profile',
            onTap: () => onSelected(3),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.isActive,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  final bool isActive;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgColor =
        isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    return Material(
      color: isActive
          ? colorScheme.primary.withAlpha((0.10 * 255).round())
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.primary.withAlpha((0.06 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(isActive ? activeIcon : icon, color: fgColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fgColor,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bookmarks tab ────────────────────────────────────────────────────────────

class _BookmarksTab extends ConsumerStatefulWidget {
  const _BookmarksTab();

  @override
  ConsumerState<_BookmarksTab> createState() => _BookmarksTabState();
}

class _BookmarksTabState extends ConsumerState<_BookmarksTab> {
  final List<_BmItem> _items = [];
  // Dedicated controller so the bookmarks scroll position stays isolated and
  // doesn't leak into the shared NestedScrollView (which would otherwise push
  // the next tab's content up under the header).
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;
  String? _error;
  final Set<String> _swappingIds = <String>{};
  Map<String, dynamic>? _lastReadPost;
  bool _isLastReadLoading = false;

  Future<void> _switchBookmarkPart(String oldPostId, String newPostId) async {
    if (_swappingIds.contains(oldPostId) || _swappingIds.contains(newPostId)) return;

    setState(() {
      _swappingIds.add(oldPostId);
    });

    try {
      final dio = ref.read(apiClientProvider).dio;
      final repo = ref.read(feedRepositoryProvider);

      // 1. Fetch detailed post data to construct the new _BmItem
      final response = await dio.get<Map<String, dynamic>>('/api/v1/posts/$newPostId');
      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};

      if (data.isEmpty) {
        throw Exception('Failed to load target chapter details.');
      }

      final newBmItem = _BmItem.fromJson(data);

      // 2. Perform backend bookmark swaps
      await repo.addBookmark(postId: newPostId);
      await repo.removeBookmark(postId: oldPostId);

      if (!mounted) return;

      // 3. Update the item in the list
      setState(() {
        final idx = _items.indexWhere((x) => x.id == oldPostId);
        if (idx >= 0) {
          _items[idx] = newBmItem;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Swapped chapter to: "${newBmItem.title}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch sequel part: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _swappingIds.remove(oldPostId);
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _items.clear();
        _nextCursor = null;
        _hasMore = false;
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final lastRead = await LastReadingStore.load();
      if (mounted) {
        setState(() {
          _lastReadPost = lastRead;
        });
      }

      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get<Map<String, dynamic>>(
        '/api/v1/bookmarks',
        queryParameters: <String, dynamic>{
          'limit': 20,
          if (_nextCursor != null && !refresh) 'cursor': _nextCursor,
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final itemsJson =
          (data['items'] is List) ? data['items'] as List : const <dynamic>[];
      final items = itemsJson
          .whereType<Map<String, dynamic>>()
          .map(_BmItem.fromJson)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items
            ..clear()
            ..addAll(items);
        } else {
          _items.addAll(items);
        }
        _nextCursor = data['next_cursor']?.toString();
        _hasMore = data['has_more'] == true;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ── Loading ──────────────────────────────────────────────────────────────
    // All branches return a CustomScrollView with the dedicated scroll
    // controller so they always respect the outer NestedScrollView header and
    // their tops start below the pinned app bar instead of at the screen origin.
    if (_isLoading) {
      return CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    // ── Error ────────────────────────────────────────────────────────────────
    if (_error != null) {
      return CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.error_outline,
                        size: 40, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => _load(refresh: true),
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

    // ── Empty ────────────────────────────────────────────────────────────────
    if (_items.isEmpty && _lastReadPost == null) {
      return RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 98),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.bookmark_border,
                      size: 56,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your shelf is empty',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Swipe up on any story to save it here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if ((n is ScrollUpdateNotification || n is OverscrollNotification) &&
              n.metrics.extentAfter < 600) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 600,
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_lastReadPost != null) ...[
                    _buildContinueReadingSection(context, theme, colorScheme),
                    const SizedBox(height: 24),
                  ],
                  if (_items.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.bookmarks_outlined,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SAVED STORIES',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_items.isEmpty && _lastReadPost != null) ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_border,
                            size: 40,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Saved Shelf is Empty',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Swipe down on any card to save it here.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            if (_items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 98),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _items[index];
                      return Padding(
                        key: ValueKey<String>('bm-pad-${item.id}'),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _BmCard(
                          key: ValueKey<String>('bm-${item.id}'),
                          item: item,
                          isLoading: _swappingIds.contains(item.id),
                          onSwitchPart: (newId) => _switchBookmarkPart(item.id, newId),
                          onRemove: () async {
                            final idx = _items.indexOf(item);
                            if (idx < 0) return;
                            setState(() => _items.removeAt(idx));
                            try {
                              final repo = ref.read(feedRepositoryProvider);
                              await repo.removeBookmark(postId: item.id);
                            } catch (_) {
                              if (mounted) {
                                setState(() {
                                  final reInsertIdx = idx.clamp(0, _items.length);
                                  _items.insert(reInsertIdx, item);
                                });
                              }
                            }
                          },
                        ),
                      );
                    },
                    childCount: _items.length,
                  ),
                ),
              ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueReadingSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isDark = cardBrightness == Brightness.dark;

    final cardBg = isDark ? cardCharcoalDark : cardCreamLight;
    final cardText = isDark ? cardCharcoalText : cardCreamText;
    final cardSub = isDark ? cardCharcoalSubtext : cardCreamSubtext;
    final accentColor = isDark ? cardCharcoalAccent : cardCreamAccent;

    final post = _lastReadPost!;
    final title = post['title']?.toString() ?? 'Untitled';
    final authorName = post['author_name']?.toString() ?? 'Unknown Author';
    final postId = post['id']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              color: accentColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'CONTINUE READING',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _isLastReadLoading
                ? null
                : () async {
                    setState(() => _isLastReadLoading = true);
                    try {
                      // 1. Align discover deck top card
                      await ref
                          .read(swipeDeckControllerProvider.notifier)
                          .setTopCard(postId);

                      // 2. Change bottom nav tab to discover
                      ref.read(bottomNavIndexProvider.notifier).state = 0;

                      // 3. Navigate into reader view
                      if (context.mounted) {
                        context.push(
                          '/post/$postId',
                          extra: <String, String>{
                            'authorId': post['author_id']?.toString() ?? '',
                            'authorName': authorName,
                          },
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to load story: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isLastReadLoading = false);
                      }
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.lora(
                            textStyle: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cardText,
                            ),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'by $authorName',
                          style: GoogleFonts.inter(
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: cardSub,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_isLastReadLoading)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    )
                  else
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: isDark ? const Color(0xFF1E1C16) : Colors.white,
                        size: 26,
                      ),
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

// ─── Bookmark data model + card ───────────────────────────────────────────────

class _BmItem {
  const _BmItem({
    required this.id,
    required this.title,
    required this.authorName,
    this.parentId,
    this.nextPostId,
    required this.authorId,
  });
  final String id;
  final String title;
  final String authorName;
  final String? parentId;
  final String? nextPostId;
  final String authorId;

  _BmItem copyWith({
    String? id,
    String? title,
    String? authorName,
    String? parentId,
    String? nextPostId,
    String? authorId,
  }) {
    return _BmItem(
      id: id ?? this.id,
      title: title ?? this.title,
      authorName: authorName ?? this.authorName,
      parentId: parentId ?? this.parentId,
      nextPostId: nextPostId ?? this.nextPostId,
      authorId: authorId ?? this.authorId,
    );
  }

  factory _BmItem.fromJson(Map<String, dynamic> json) => _BmItem(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        authorName: (json['author_name'] ?? '').toString(),
        parentId: json['parent_id']?.toString(),
        nextPostId: json['next_post_id']?.toString(),
        authorId: (json['author_id'] ?? '').toString(),
      );
}

class _BmCard extends ConsumerWidget {
  const _BmCard({
    super.key,
    required this.item,
    required this.onRemove,
    this.onSwitchPart,
    this.isLoading = false,
  });
  final _BmItem item;
  final VoidCallback onRemove;
  final ValueChanged<String>? onSwitchPart;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cardBrightness =
        ref.watch(cardBrightnessProvider).valueOrNull ?? Brightness.dark;
    final isCardDark = cardBrightness == Brightness.dark;

    final cardBg = isCardDark ? cardCharcoalDark : cardCreamLight;
    final cardBorder = isCardDark ? cardCharcoalEdge : cardCreamEdge;
    final cardText = isCardDark ? cardCharcoalText : cardCreamText;
    final cardSub = isCardDark ? cardCharcoalSubtext : cardCreamSubtext;

    final isChained = item.parentId != null || item.nextPostId != null;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (isLoading) return;
          final velocity = details.primaryVelocity ?? 0.0;
          if (velocity < -300) {
            // Swipe Left -> next part (sequel)
            if (item.nextPostId != null) {
              onSwitchPart?.call(item.nextPostId!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This is the end of the story chain.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else if (velocity > 300) {
            // Swipe Right -> previous part (parent)
            if (item.parentId != null) {
              onSwitchPart?.call(item.parentId!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This is the start of the story chain.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isLoading ? null : () => context.push('/post/${item.id}'),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isLoading ? 0.35 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 14, 8, 14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.title,
                              style: GoogleFonts.lora(
                                textStyle: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cardText,
                                ),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.authorName.isNotEmpty || isChained) ...<Widget>[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (item.authorName.isNotEmpty)
                                    Text(
                                      item.authorName,
                                      style: GoogleFonts.inter(
                                        textStyle: theme.textTheme.labelMedium?.copyWith(
                                          color: cardSub,
                                        ),
                                      ),
                                    ),
                                  if (item.authorName.isNotEmpty && isChained)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        '•',
                                        style: TextStyle(
                                          color: cardSub,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  if (isChained)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withAlpha((0.12 * 255).round()),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.swap_horizontal_circle_outlined,
                                            size: 11,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Swipe Card to Navigate Parts',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.primary,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.bookmark,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: isLoading ? null : onRemove,
                        tooltip: 'Remove bookmark',
                      ),
                    ],
                  ),
                ),
              ),
              if (item.parentId != null)
                Positioned(
                  left: 6,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: colorScheme.primary.withAlpha((0.55 * 255).round()),
                      size: 20,
                    ),
                  ),
                ),
              if (item.nextPostId != null)
                Positioned(
                  right: 40,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.primary.withAlpha((0.55 * 255).round()),
                      size: 20,
                    ),
                  ),
                ),
              if (isLoading)
                Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Nav item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final fgColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.65);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected
              ? colorScheme.onSurface.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    selected ? activeIcon : icon,
                    size: 20,
                    color: fgColor,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: fgColor,
                    ),
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

