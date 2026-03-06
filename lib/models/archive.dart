class ArchiveEntry {
  ArchiveEntry({
    required this.videoId,
    required this.archivedAt,
    this.title,
    this.thumbnailUrl,
    this.channelId,
    this.channelTitle,
    this.channelThumbnailUrl,
  });

  final String videoId;
  final DateTime archivedAt;
  final String? title;
  final String? thumbnailUrl;
  final String? channelId;
  final String? channelTitle;
  final String? channelThumbnailUrl;
}
