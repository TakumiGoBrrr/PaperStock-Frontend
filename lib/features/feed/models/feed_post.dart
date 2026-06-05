import 'package:flutter/foundation.dart';

@immutable
class FeedPost {
  const FeedPost({
    required this.id,
    required this.title,
    required this.bodyPreview,
    required this.tags,
    required this.authorId,
    required this.authorName,
    required this.readTimeMinutes,
    this.likesCount = 0,
    this.isArchived = false,
    this.isNsfw = false,
    this.moderationStatus = 'approved',
    this.moderationNote,
    this.rejectedAt,
    this.canEditAfterRejection = false,
  });

  final String id;
  final String title;
  final String bodyPreview;
  final List<String> tags;
  final String authorId;
  final String authorName;
  final int readTimeMinutes;
  final int likesCount;
  final bool isArchived;
  final bool isNsfw;
  final String moderationStatus;
  final String? moderationNote;
  final DateTime? rejectedAt;
  final bool canEditAfterRejection;
}
