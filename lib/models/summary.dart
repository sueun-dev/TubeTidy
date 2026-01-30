class VideoSummary {
  VideoSummary({
    required this.videoId,
    required this.language,
    required this.lines,
    required this.createdAt,
  });

  final String videoId;
  final String language;
  final List<String> lines;
  final DateTime createdAt;
}
