import 'package:flutter/foundation.dart';

@immutable
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: (json['id'] ?? '').toString(),
      postId: (json['post_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_display_name'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
