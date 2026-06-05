import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.followersCount,
    required this.followingCount,
    required this.isFollowing,
  });

  final String id;
  final String? displayName;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? bio,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }

  factory UserProfile.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) {
    return UserProfile(
      id: ((json['id'] as Object?)?.toString() ?? fallbackId ?? '').trim(),
      displayName: (json['display_name'] as Object?)?.toString(),
      bio: (json['bio'] as Object?)?.toString(),
      followersCount: (json['followers_count'] is num)
          ? (json['followers_count'] as num).toInt()
          : int.tryParse((json['followers_count'] ?? '0').toString()) ?? 0,
      followingCount: (json['following_count'] is num)
          ? (json['following_count'] as num).toInt()
          : int.tryParse((json['following_count'] ?? '0').toString()) ?? 0,
      isFollowing: json['is_following'] == true,
    );
  }
}
