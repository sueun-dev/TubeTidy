class Video {
  Video({
    required this.id,
    required this.youtubeId,
    required this.channelId,
    required this.title,
    required this.publishedAt,
    required this.thumbnailUrl,
  });

  final String id;
  final String youtubeId;
  final String channelId;
  final String title;
  final DateTime publishedAt;
  final String thumbnailUrl;
}
