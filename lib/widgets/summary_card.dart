import 'package:flutter/cupertino.dart';

import '../models/channel.dart';
import '../models/transcript.dart';
import '../models/video.dart';
import '../theme.dart';
import 'glass_surface.dart';
import '../localization/app_strings.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.video,
    required this.channel,
    required this.transcript,
    required this.isTranscriptLoading,
    required this.isQueued,
    required this.strings,
    required this.onWatchVideo,
    required this.isArchived,
    required this.onToggleArchive,
    required this.onRequestSummary,
  });

  final Video video;
  final Channel channel;
  final TranscriptResult? transcript;
  final bool isTranscriptLoading;
  final bool isQueued;
  final AppStrings strings;
  final VoidCallback onWatchVideo;
  final bool isArchived;
  final VoidCallback onToggleArchive;
  final VoidCallback onRequestSummary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatTimestamp(video.publishedAt);

    return GlassSurface(
      settings: LiquidGlassPresets.panel,
      borderRadius: BorderRadius.circular(LiquidRadius.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(
                  thumbUrl: video.thumbnailUrl,
                  videoId: video.youtubeId,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: LiquidTextStyles.headline.copyWith(
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${channel.title} · $dateLabel',
                              style: LiquidTextStyles.caption1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ArchiveButton(
                  isArchived: isArchived,
                  onTap: onToggleArchive,
                ),
              ],
            ),
          ),

          // Meta chips
          if (transcript != null && transcript!.source != 'error')
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: _TranscriptMeta(transcript: transcript, strings: strings),
            ),

          // Transcript body
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: GlassSurfaceThin(
              padding: const EdgeInsets.all(14),
              borderRadius: BorderRadius.circular(LiquidRadius.md),
              child: _TranscriptBody(
                transcript: transcript,
                isLoading: isTranscriptLoading,
                isQueued: isQueued,
                strings: strings,
                onRequestSummary: onRequestSummary,
              ),
            ),
          ),

          // Watch button
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: SizedBox(
              width: double.infinity,
              child: LiquidGlassButton(
                onPressed: onWatchVideo,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.play_fill,
                      size: 14,
                      color: LiquidColors.brand,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.watchVideo,
                      style: LiquidTextStyles.footnote.copyWith(
                        fontWeight: FontWeight.w600,
                        color: LiquidColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final isAm = date.hour < 12;
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = strings.isEn ? (isAm ? 'AM' : 'PM') : (isAm ? '오전' : '오후');
    return '$month.$day · $period $hour12:$minute';
  }
}

class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.isArchived,
    required this.onTap,
  });

  final bool isArchived;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isArchived
              ? LiquidColors.accent.withValues(alpha: 0.15)
              : LiquidColors.glassDark,
          borderRadius: BorderRadius.circular(LiquidRadius.sm),
        ),
        child: Icon(
          isArchived ? CupertinoIcons.star_fill : CupertinoIcons.star,
          size: 20,
          color: isArchived ? LiquidColors.accent : LiquidColors.textTertiary,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.thumbUrl, required this.videoId});

  final String thumbUrl;
  final String videoId;

  String get resolvedUrl {
    if (thumbUrl.isNotEmpty) return thumbUrl;
    if (videoId.isNotEmpty) {
      return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final url = resolvedUrl;
    final placeholder = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: LiquidColors.glassDark,
        borderRadius: BorderRadius.circular(LiquidRadius.md),
      ),
      alignment: Alignment.center,
      child: const Icon(
        CupertinoIcons.photo,
        color: LiquidColors.textTertiary,
        size: 24,
      ),
    );

    if (url.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(LiquidRadius.md),
      child: Image.network(
        url,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder;
        },
      ),
    );
  }
}

class _TranscriptMeta extends StatelessWidget {
  const _TranscriptMeta({required this.transcript, required this.strings});

  final TranscriptResult? transcript;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (transcript == null || transcript!.source == 'error') {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[];
    if ((transcript!.summary ?? '').trim().isNotEmpty) {
      chips.add(GlassMetaChip(
        label: strings.metaSummary,
        color: LiquidColors.success,
      ));
    }
    final sourceLabel = transcript!.source == 'whisper'
        ? strings.metaSpeech
        : strings.metaCaptions;
    chips.add(GlassMetaChip(label: sourceLabel));

    if (transcript!.partial) {
      chips.add(GlassMetaChip(
        label: strings.metaPartial,
        color: LiquidColors.accent,
      ));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _TranscriptBody extends StatelessWidget {
  const _TranscriptBody({
    required this.transcript,
    required this.isLoading,
    required this.isQueued,
    required this.strings,
    required this.onRequestSummary,
  });

  final TranscriptResult? transcript;
  final bool isLoading;
  final bool isQueued;
  final AppStrings strings;
  final VoidCallback onRequestSummary;

  @override
  Widget build(BuildContext context) {
    if (isQueued && !isLoading && transcript == null) {
      return Row(
        children: [
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 10),
          Text(
            strings.queued,
            style: LiquidTextStyles.caption1,
          ),
        ],
      );
    }

    if (isLoading && transcript == null) {
      return Row(
        children: [
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.generatingTranscript,
              style: LiquidTextStyles.caption1,
            ),
          ),
        ],
      );
    }

    if (transcript != null && transcript!.source == 'error') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 14,
                color: LiquidColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  transcript!.text,
                  style: LiquidTextStyles.caption1.copyWith(
                    color: LiquidColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LiquidGlassButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: onRequestSummary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.arrow_clockwise,
                  size: 14,
                  color: LiquidColors.brand,
                ),
                const SizedBox(width: 6),
                Text(
                  strings.retrySummarize,
                  style: LiquidTextStyles.caption1.copyWith(
                    fontWeight: FontWeight.w600,
                    color: LiquidColors.brand,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (transcript == null || transcript!.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.notGenerated,
            style: LiquidTextStyles.caption1,
          ),
          const SizedBox(height: 12),
          LiquidGlassButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: onRequestSummary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.sparkles,
                  size: 14,
                  color: LiquidColors.brand,
                ),
                const SizedBox(width: 6),
                Text(
                  strings.summarize,
                  style: LiquidTextStyles.caption1.copyWith(
                    fontWeight: FontWeight.w600,
                    color: LiquidColors.brand,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final summary = (transcript!.summary ?? '').trim();
    final displayText = summary.isNotEmpty ? summary : transcript!.text;

    return Text(
      displayText,
      style: LiquidTextStyles.subheadline.copyWith(
        height: 1.5,
      ),
    );
  }
}
