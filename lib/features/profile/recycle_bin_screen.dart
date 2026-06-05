import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../feed/repository/feed_repository.dart';

class RecycleBinScreen extends ConsumerStatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  ConsumerState<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends ConsumerState<RecycleBinScreen> {
  static const _limit = 20;
  static const _threshold = 600.0;

  final _scrollController = ScrollController();

  List<TrashItem> _items = const <TrashItem>[];
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _initialLoading = true;
  String? _error;

  final Set<String> _inFlight = <String>{};

  FeedRepository get _repo =>
      FeedRepository(dio: ref.read(apiClientProvider).dio);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage(cursor: null);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels < _threshold) {
      _fetchNext();
    }
  }

  Future<void> _loadPage({required String? cursor}) async {
    if (!mounted) return;

    try {
      final page = await _repo.getTrash(cursor: cursor, limit: _limit);

      if (!mounted) return;
      setState(() {
        if (cursor == null) {
          _items = page.items;
        } else {
          _items = <TrashItem>[..._items, ...page.items];
        }
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _initialLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _fetchNext() async {
    if (!_hasMore || _isLoadingMore) return;
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    setState(() => _isLoadingMore = true);
    await _loadPage(cursor: cursor);
  }

  Future<void> _refresh() async {
    setState(() {
      _initialLoading = true;
      _items = const <TrashItem>[];
      _nextCursor = null;
      _hasMore = false;
      _isLoadingMore = false;
      _error = null;
    });
    await _loadPage(cursor: null);
  }

  Future<void> _restore(TrashItem item) async {
    if (_inFlight.contains(item.id)) return;
    _inFlight.add(item.id);

    setState(() => _items = _items.where((i) => i.id != item.id).toList());

    try {
      await _repo.restorePost(postId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${item.title}" restored.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = <TrashItem>[item, ..._items]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restore. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _inFlight.remove(item.id);
    }
  }

  Future<void> _permanentDelete(TrashItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '"${item.title}" will be deleted forever and cannot be recovered.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => ctx.pop(true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (_inFlight.contains(item.id)) return;
    _inFlight.add(item.id);

    setState(() => _items = _items.where((i) => i.id != item.id).toList());

    try {
      await _repo.permanentlyDeletePost(postId: item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = <TrashItem>[item, ..._items]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _inFlight.remove(item.id);
    }
  }

  String _daysRemaining(DateTime deletedAt) {
    final expiry = deletedAt.add(const Duration(days: 30));
    final remaining = expiry.difference(DateTime.now()).inDays;
    if (remaining <= 0) return 'Expires soon';
    if (remaining == 1) return '1 day left';
    return '$remaining days left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Widget body;

    if (_initialLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Something went wrong', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    } else if (_items.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.delete_outline,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'Recycle bin is empty',
              style: GoogleFonts.lora(
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Posts are permanently deleted after 30 days.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 98),
          itemCount: _items.length + (_isLoadingMore ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            // Banner at top
            if (index == 0) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Posts here are permanently deleted after 30 days.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final dataIndex = index - 1;

            if (dataIndex >= _items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              );
            }

            final item = _items[dataIndex];

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  child: _TrashCard(
                    item: item,
                    isDark: isDark,
                    daysRemaining: _daysRemaining(item.deletedAt),
                    inFlight: _inFlight.contains(item.id),
                    onRestore: () => _restore(item),
                    onDelete: () => _permanentDelete(item),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: GlassAppBar(
        left: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        title: Text(
          'Recycle Bin',
          style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: body,
      ),
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({
    required this.item,
    required this.isDark,
    required this.daysRemaining,
    required this.inFlight,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashItem item;
  final bool isDark;
  final String daysRemaining;
  final bool inFlight;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? cardBlack : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? borderBlack : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.title,
                    style: GoogleFonts.lora(
                      textStyle: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (inFlight)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 8),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (item.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: item.tags.take(5).map((tag) {
                  return Text(
                    '#$tag',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? primaryPurple.withValues(alpha: 0.85)
                          : colorScheme.primary.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule_outlined,
                  size: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 4),
                Text(
                  daysRemaining,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: inFlight ? null : onRestore,
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 2),
                TextButton.icon(
                  onPressed: inFlight ? null : onDelete,
                  icon: Icon(
                    Icons.delete_forever_outlined,
                    size: 15,
                    color: colorScheme.error,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
