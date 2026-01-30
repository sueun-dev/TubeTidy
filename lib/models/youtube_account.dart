class YouTubeAccount {
  YouTubeAccount({
    required this.id,
    required this.userId,
    required this.youtubeChannelId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String id;
  final String userId;
  final String youtubeChannelId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}
