import 'package:flutter/foundation.dart';

@immutable
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.tags,
    required this.readTimeMinutes,
    required this.likesCount,
    required this.isLiked,
    required this.isBookmarked,
    required this.isArchived,
    this.isNsfw = false,
    required this.moderationStatus,
    this.moderationNote,
    required this.createdAt,
    required this.updatedAt,
    this.rejectedAt,
    this.canEditAfterRejection = false,
    this.debugScoreInfo,
    this.parentId,
    this.nextPostId,
    this.firstPostId,
    this.storyType,
    this.isAd = false,
    this.adImageUrl,
    this.adTargetUrl,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String body;
  final List<String> tags;
  final int readTimeMinutes;
  final int likesCount;
  final bool isLiked;
  final bool isBookmarked;
  final bool isArchived;
  final bool isNsfw;
  final String moderationStatus;
  final String? moderationNote;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? rejectedAt;
  final bool canEditAfterRejection;
  final String? debugScoreInfo;
  final String? parentId;
  final String? nextPostId;
  final String? firstPostId;
  final String? storyType;
  final bool isAd;
  final String? adImageUrl;
  final String? adTargetUrl;

  Post copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? title,
    String? body,
    List<String>? tags,
    int? readTimeMinutes,
    int? likesCount,
    bool? isLiked,
    bool? isBookmarked,
    bool? isArchived,
    bool? isNsfw,
    String? moderationStatus,
    String? moderationNote,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? rejectedAt,
    bool? canEditAfterRejection,
    String? debugScoreInfo,
    String? parentId,
    String? nextPostId,
    String? firstPostId,
    String? storyType,
    bool? isAd,
    String? adImageUrl,
    String? adTargetUrl,
  }) {
    return Post(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      readTimeMinutes: readTimeMinutes ?? this.readTimeMinutes,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isArchived: isArchived ?? this.isArchived,
      isNsfw: isNsfw ?? this.isNsfw,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      moderationNote: moderationNote ?? this.moderationNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      canEditAfterRejection: canEditAfterRejection ?? this.canEditAfterRejection,
      debugScoreInfo: debugScoreInfo ?? this.debugScoreInfo,
      parentId: parentId ?? this.parentId,
      nextPostId: nextPostId ?? this.nextPostId,
      firstPostId: firstPostId ?? this.firstPostId,
      storyType: storyType ?? this.storyType,
      isAd: isAd ?? this.isAd,
      adImageUrl: adImageUrl ?? this.adImageUrl,
      adTargetUrl: adTargetUrl ?? this.adTargetUrl,
    );
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: (json['id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      readTimeMinutes: (json['read_time'] is num)
          ? (json['read_time'] as num).toInt()
          : int.tryParse((json['read_time'] ?? '0').toString()) ?? 0,
      likesCount: (json['likes_count'] is num)
          ? (json['likes_count'] as num).toInt()
          : int.tryParse((json['likes_count'] ?? '0').toString()) ?? 0,
      isLiked: json['is_liked'] == true,
      isBookmarked: json['is_bookmarked'] == true,
      isArchived: json['is_archived'] == true,
      isNsfw: json['is_nsfw'] == true,
      moderationStatus: (json['moderation_status'] ?? 'approved').toString(),
      moderationNote: json['moderation_note']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      rejectedAt: json['rejected_at'] != null
          ? DateTime.tryParse(json['rejected_at'].toString())
          : null,
      canEditAfterRejection: json['can_edit_after_rejection'] == true,
      debugScoreInfo: json['debug_score_info']?.toString(),
      parentId: json['parent_id']?.toString(),
      nextPostId: json['next_post_id']?.toString(),
      firstPostId: json['first_post_id']?.toString(),
      storyType: json['story_type']?.toString(),
      isAd: json['is_ad'] == true,
      adImageUrl: json['image_url']?.toString(),
      adTargetUrl: json['target_url']?.toString(),
    );
  }
}
