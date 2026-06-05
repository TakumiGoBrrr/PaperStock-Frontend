class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorDisplayName,
    required this.postId,
    this.postTitle,
    this.postModerationNote,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type; // follow | like | comment | sequel | moderation_rejected | moderation_deleted
  final String actorId;
  final String actorDisplayName;
  final String? postId;
  final String? postTitle;
  final String? postModerationNote;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as Object?)?.toString() ?? '',
      type: (json['type'] as Object?)?.toString() ?? '',
      actorId: (json['actor_id'] as Object?)?.toString() ?? '',
      actorDisplayName:
          (json['actor_display_name'] as Object?)?.toString() ?? '',
      postId: (json['post_id'] as Object?)?.toString(),
      postTitle: (json['post_title'] as Object?)?.toString(),
      postModerationNote: (json['post_moderation_note'] as Object?)?.toString(),
      isRead: (json['is_read'] as Object?) == true,
      createdAt: DateTime.tryParse(
              (json['created_at'] as Object?)?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AppNotification copyWith({
    String? id,
    String? type,
    String? actorId,
    String? actorDisplayName,
    String? postId,
    String? postTitle,
    String? postModerationNote,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      actorId: actorId ?? this.actorId,
      actorDisplayName: actorDisplayName ?? this.actorDisplayName,
      postId: postId ?? this.postId,
      postTitle: postTitle ?? this.postTitle,
      postModerationNote: postModerationNote ?? this.postModerationNote,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
