class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'access_token': accessToken,
      'refresh_token': refreshToken,
    };
  }
}
