class TranscriptResult {
  const TranscriptResult({
    required this.text,
    this.summary,
    required this.source,
    required this.partial,
  });

  final String text;
  final String? summary;
  final String source; // captions | whisper
  final bool partial;
}
