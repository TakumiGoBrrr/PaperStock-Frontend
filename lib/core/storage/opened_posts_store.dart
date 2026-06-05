import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OpenedPostsStore {
  static const String _openedKey = 'opened_post_ids';
  static const String _hiddenKey = 'hidden_post_ids';

  static const int _maxOpenedIds = 300;
  static const int _maxHiddenIds = 500;

  static Future<void> clear() async {
    openedIds.value = <String>{};
    hiddenIds.value = <String>{};
    _recomputeExcluded();

    // Allow a future session to reload from disk.
    _loadFuture = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_openedKey);
    await prefs.remove(_hiddenKey);
  }

  /// Posts opened by the user (recency ordered).
  static final ValueNotifier<Set<String>> openedIds =
      ValueNotifier<Set<String>>(<String>{});

  /// Posts hidden permanently from the feed.
  static final ValueNotifier<Set<String>> hiddenIds =
      ValueNotifier<Set<String>>(<String>{});

  /// Union of [openedIds] and [hiddenIds] used for feed filtering.
  static final ValueNotifier<Set<String>> excludedIds =
      ValueNotifier<Set<String>>(<String>{});

  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  static Future<void> markOpened(String postId) async {
    final id = postId.trim();
    if (id.isEmpty) return;

    await ensureLoaded();

    final nextOpened = <String>{...openedIds.value}
      ..remove(id)
      ..add(id);

    while (nextOpened.length > _maxOpenedIds) {
      final first = nextOpened.isEmpty ? null : nextOpened.first;
      if (first == null) break;
      nextOpened.remove(first);
    }

    openedIds.value = nextOpened;
    _recomputeExcluded();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_openedKey, nextOpened.toList(growable: false));
  }

  /// Removes a post from history only.
  ///
  /// - Removes the post from [openedIds].
  /// - Does NOT add it to [hiddenIds].
  /// - The post may appear again in the feed.
  static Future<void> removeFromHistoryOnly(String postId) async {
    final id = postId.trim();
    if (id.isEmpty) return;

    await ensureLoaded();

    final nextOpened = <String>{...openedIds.value}..remove(id);

    openedIds.value = nextOpened;
    _recomputeExcluded();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_openedKey, nextOpened.toList(growable: false));
  }

  /// Hides a post permanently.
  ///
  /// - Removes the post from [openedIds].
  /// - Adds the post to [hiddenIds] so it stays excluded from the feed.
  static Future<void> hidePermanently(String postId) async {
    final id = postId.trim();
    if (id.isEmpty) return;

    await ensureLoaded();

    final nextOpened = <String>{...openedIds.value}..remove(id);

    final nextHidden = <String>{...hiddenIds.value}
      ..remove(id)
      ..add(id);

    while (nextHidden.length > _maxHiddenIds) {
      final first = nextHidden.isEmpty ? null : nextHidden.first;
      if (first == null) break;
      nextHidden.remove(first);
    }

    openedIds.value = nextOpened;
    hiddenIds.value = nextHidden;
    _recomputeExcluded();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_openedKey, nextOpened.toList(growable: false));
    await prefs.setStringList(_hiddenKey, nextHidden.toList(growable: false));
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final rawOpened = prefs.getStringList(_openedKey) ?? const <String>[];
    final rawHidden = prefs.getStringList(_hiddenKey) ?? const <String>[];

    final opened = <String>{};
    for (final v in rawOpened) {
      final id = v.trim();
      if (id.isEmpty) continue;
      opened.remove(id);
      opened.add(id);
      if (opened.length >= _maxOpenedIds) break;
    }

    final hidden = <String>{};
    for (final v in rawHidden) {
      final id = v.trim();
      if (id.isEmpty) continue;
      hidden.remove(id);
      hidden.add(id);
      if (hidden.length >= _maxHiddenIds) break;
    }

    openedIds.value = opened;
    hiddenIds.value = hidden;
    _recomputeExcluded();
  }

  static void _recomputeExcluded() {
    excludedIds.value = <String>{
      ...openedIds.value,
      ...hiddenIds.value,
    };
  }
}
