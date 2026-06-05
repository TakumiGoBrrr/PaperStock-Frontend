import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LastReadingStore {
  static const String _key = 'last_read_post_json';

  static Future<void> save({
    required String id,
    required String title,
    required String authorName,
    required String authorId,
    required String? parentId,
    required String? nextPostId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'id': id,
      'title': title,
      'author_name': authorName,
      'author_id': authorId,
      'parent_id': parentId,
      'next_post_id': nextPostId,
    };
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
