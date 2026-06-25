import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client_provider.dart';
import '../feed/models/post.dart';
import 'swipe_repository.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final swipeRepositoryProvider = Provider<SwipeRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return SwipeRepository(dio: dio);
});

final swipeDeckControllerProvider =
    AutoDisposeAsyncNotifierProvider<SwipeDeckController, SwipeDeckState>(
  SwipeDeckController.new,
);

// ─── State ────────────────────────────────────────────────────────────────────

class SwipeDeckState {
  const SwipeDeckState({
    required this.deck,
    required this.lastSwiped,
    required this.isFetchingMore,
  });

  /// Cards still to show. Index 0 is the top card.
  final List<Post> deck;

  /// The most recently swiped post — used by undo to re-insert it.
  final Post? lastSwiped;

  /// True while a background refill is in progress.
  final bool isFetchingMore;

  SwipeDeckState copyWith({
    List<Post>? deck,
    Post? lastSwiped,
    bool clearLastSwiped = false,
    bool? isFetchingMore,
  }) {
    return SwipeDeckState(
      deck: deck ?? this.deck,
      lastSwiped: clearLastSwiped ? null : (lastSwiped ?? this.lastSwiped),
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  bool get isEmpty => deck.isEmpty;

  static const SwipeDeckState empty = SwipeDeckState(
    deck: <Post>[],
    lastSwiped: null,
    isFetchingMore: false,
  );
}

// ─── Controller ───────────────────────────────────────────────────────────────

class SwipeDeckController extends AutoDisposeAsyncNotifier<SwipeDeckState> {
  /// IDs swiped during this session. The server records swipes asynchronously,
  /// so a low-deck refill can fire its `GET /deck` before the swipe is
  /// persisted — without this guard the backend would hand the just-swiped
  /// story straight back and the card would reappear.
  final Set<String> _swipedThisSession = <String>{};

  List<Post> _mergeStoriesAndAds(List<Post> stories, List<Post> ads) {
    if (ads.isEmpty) return stories;
    final result = <Post>[];
    int adIndex = 0;
    for (int i = 0; i < stories.length; i++) {
      result.add(stories[i]);
      if ((result.length - adIndex) % 7 == 0) {
        final ad = ads[adIndex % ads.length];
        final uniqueAd = ad.copyWith(
          id: '${ad.id}_${DateTime.now().microsecondsSinceEpoch}_$i',
        );
        result.add(uniqueAd);
        adIndex++;
      }
    }
    return result;
  }

  @override
  Future<SwipeDeckState> build() async {
    final repo = ref.watch(swipeRepositoryProvider);
    try {
      final page = await repo.getDeck(limit: 20);
      final ads = await repo.getActiveAds();
      final merged = _mergeStoriesAndAds(page.stories, ads);
      return SwipeDeckState(
        deck: merged,
        lastSwiped: null,
        isFetchingMore: false,
      );
    } on DioException catch (e) {
      // 401 means the auth guard will redirect to login — don't crash the UI.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return SwipeDeckState.empty;
      }
      // Re-throw anything else (network down, 500, etc.) so the error UI shows.
      rethrow;
    }
  }

  // ── Public actions ──────────────────────────────────────────────────────────

  /// Called immediately when a card is flung (before API round-trip).
  /// Optimistically removes the top card and fires the API in the background.
  Future<void> swipe({
    required String storyId,
    required String direction,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final index = current.deck.indexWhere((p) => p.id == storyId);
    if (index < 0) return;

    final swiped = current.deck[index];
    final newDeck = List<Post>.of(current.deck)..removeAt(index);

    // Remember it so a concurrent refill can't re-add it before the server
    // has recorded the swipe.
    _swipedThisSession.add(swiped.id);

    // Optimistic update — card is already off screen
    state = AsyncData(
      current.copyWith(
        deck: newDeck,
        lastSwiped: swiped,
      ),
    );

    // Refill when running low
    if (newDeck.length <= 3) {
      _refillDeck(currentDeck: newDeck);
    }

    if (swiped.isAd) {
      final realAdId = swiped.id.split('_').first;
      final repo = ref.read(swipeRepositoryProvider);
      
      // Since they swiped it, they viewed it (Impression)
      repo.recordAdImpression(realAdId);

      if (direction == 'up' && swiped.adTargetUrl != null) {
        // Swipe up acts as "Learn More" — a click redirect.
        repo.recordAdClick(realAdId);
        try {
          final uri = Uri.parse(swiped.adTargetUrl!);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // Ignore launch failures
        }
      }
      return;
    }

    // Fire-and-forget API call — swipe is already recorded locally
    try {
      final repo = ref.read(swipeRepositoryProvider);
      await repo.recordSwipe(storyId: storyId, direction: direction);
    } catch (_) {
      // Swipe is still recorded in-memory; silent fail is acceptable here.
      // A full retry mechanism can be added later.
    }
  }

  Future<void> replaceTopCardWithSequel(String newPostId) async {
    final current = state.valueOrNull;
    if (current == null || current.deck.isEmpty) return;

    final dio = ref.read(apiClientProvider).dio;

    try {
      final response = await dio.get<Map<String, dynamic>>('/api/v1/posts/$newPostId');
      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};

      if (data.isEmpty) return;
      final sequelPost = Post.fromJson(data);

      final newDeck = List<Post>.of(current.deck);
      if (newDeck.isNotEmpty) {
        newDeck.removeAt(0);
      }
      newDeck.insert(0, sequelPost);

      state = AsyncData(current.copyWith(deck: newDeck));
    } catch (_) {
      // Silently ignore failures to preserve deck stability
    }
  }

  Future<void> bookmarkTopCard() async {
    final current = state.valueOrNull;
    final post = (current != null && current.deck.isNotEmpty) ? current.deck[0] : null;
    if (current == null || post == null) return;

    final nextBookmarked = !post.isBookmarked;
    final optimistic = post.copyWith(isBookmarked: nextBookmarked);

    final newDeck = List<Post>.of(current.deck);
    newDeck[0] = optimistic;
    state = AsyncData(current.copyWith(deck: newDeck));

    final dio = ref.read(apiClientProvider).dio;
    try {
      if (nextBookmarked) {
        try {
          await dio.post<void>('/api/v1/bookmarks/${post.id}');
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          await dio.post<void>('/api/v1/posts/${post.id}/bookmark');
        }
      } else {
        try {
          await dio.delete<void>('/api/v1/bookmarks/${post.id}');
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
          await dio.delete<void>('/api/v1/posts/${post.id}/bookmark');
        }
      }
    } catch (_) {
      final rolled = state.valueOrNull;
      if (rolled == null) return;
      final rolledDeck = List<Post>.of(rolled.deck);
      rolledDeck[0] = post;
      state = AsyncData(rolled.copyWith(deck: rolledDeck));
      rethrow;
    }
  }

  /// Undo the most recent swipe — puts the card back on top of the deck.
  Future<void> undo() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final lastSwiped = current.lastSwiped;
    if (lastSwiped == null) return;

    // Allow the restored card back into future refills.
    _swipedThisSession.remove(lastSwiped.id);

    // Optimistically restore the card
    final newDeck = <Post>[lastSwiped, ...current.deck];
    state = AsyncData(
      current.copyWith(deck: newDeck, clearLastSwiped: true),
    );

    try {
      final repo = ref.read(swipeRepositoryProvider);
      await repo.undoSwipe();
    } catch (_) {
      // Roll back the optimistic undo
      final rolled = state.valueOrNull;
      if (rolled == null) return;
      final restoredDeck = List<Post>.of(rolled.deck)..remove(lastSwiped);
      state = AsyncData(
        rolled.copyWith(deck: restoredDeck, lastSwiped: lastSwiped),
      );
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  Future<void> _refillDeck({required List<Post> currentDeck}) async {
    final current = state.valueOrNull;
    if (current == null || current.isFetchingMore) return;

    state = AsyncData(current.copyWith(isFetchingMore: true));

    try {
      final repo = ref.read(swipeRepositoryProvider);
      final page = await repo.getDeck(limit: 20);
      final ads = await repo.getActiveAds();

      // Exclude cards already in the deck AND anything swiped this session —
      // the server may not have recorded the most recent swipes yet.
      final latestDeck = state.valueOrNull?.deck ?? currentDeck;
      final existingIds = latestDeck.map((p) => p.id).toSet();
      final fresh = page.stories
          .where((p) =>
              !existingIds.contains(p.id) && !_swipedThisSession.contains(p.id))
          .toList();
      final merged = _mergeStoriesAndAds(fresh, ads);

      final latest = state.valueOrNull;
      if (latest == null) return;

      state = AsyncData(
        latest.copyWith(
          deck: <Post>[...latest.deck, ...merged],
          isFetchingMore: false,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(latest.copyWith(isFetchingMore: false));
    }
  }

  Future<void> setTopCard(String postId) async {
    final current = state.valueOrNull;
    final dio = ref.read(apiClientProvider).dio;
    Post? targetPost;

    try {
      final response = await dio.get<Map<String, dynamic>>('/api/v1/posts/$postId');
      final body = response.data ?? const <String, dynamic>{};
      final data = (body['data'] is Map<String, dynamic>)
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};
      if (data.isNotEmpty) {
        targetPost = Post.fromJson(data);
      }
    } catch (_) {
      // Handle silently
    }

    if (targetPost == null) return;

    if (current != null) {
      final newDeck = List<Post>.of(current.deck);
      final existingIndex = newDeck.indexWhere((p) => p.id == postId);
      if (existingIndex > 0) {
        newDeck.removeAt(existingIndex);
      }
      if (existingIndex != 0) {
        newDeck.insert(0, targetPost);
      }
      state = AsyncData(current.copyWith(deck: newDeck));
    } else {
      state = AsyncData(SwipeDeckState(
        deck: [targetPost],
        lastSwiped: null,
        isFetchingMore: false,
      ));
      _refillDeck(currentDeck: [targetPost]);
    }
  }

  Future<void> clearAllSwipes() async {
    _swipedThisSession.clear();
    state = const AsyncLoading();
    try {
      final repo = ref.read(swipeRepositoryProvider);
      await repo.clearAllSwipes();
      
      // Refetch the deck now that all swipes/views are cleared
      final page = await repo.getDeck(limit: 20);
      state = AsyncData(
        SwipeDeckState(
          deck: page.stories,
          lastSwiped: null,
          isFetchingMore: false,
        ),
      );
    } catch (e, stack) {
      state = AsyncError(e, stack);
      rethrow;
    }
  }
}
