import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../models/channel.dart';
import '../models/transcript.dart';
import '../models/video.dart';
import '../theme.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.video,
    required this.channel,
    required this.transcript,
    required this.isTranscriptLoading,
    required this.isArchived,
    required this.onToggleArchive,
    required this.onRequestSummary,
  });

  final Video video;
  final Channel channel;
  final TranscriptResult? transcript;
  final bool isTranscriptLoading;
  final bool isArchived;
  final VoidCallback onToggleArchive;
  final VoidCallback onRequestSummary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MM.dd · a h:mm').format(video.publishedAt);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    video.thumbnailUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppColors.elevatedCard,
                      alignment: Alignment.center,
                      child: const Icon(CupertinoIcons.photo, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${channel.title} · $dateLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: isArchived ? '별표 저장 해제' : '별표로 저장',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onToggleArchive,
                    child: Icon(
                      isArchived ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      color: isArchived ? AppColors.accent : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _TranscriptMeta(transcript: transcript),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.elevatedCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline),
              ),
              child: _TranscriptBody(
                transcript: transcript,
                isLoading: isTranscriptLoading,
                onRequestSummary: onRequestSummary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptMeta extends StatelessWidget {
  const _TranscriptMeta({required this.transcript});

  final TranscriptResult? transcript;

  @override
  Widget build(BuildContext context) {
    if (transcript == null || transcript!.source == 'error') {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[];
    if ((transcript!.summary ?? '').trim().isNotEmpty) {
      chips.add(const _MetaChip(label: '3줄 요약'));
    }
    final sourceLabel = transcript!.source == 'whisper' ? '음성 인식' : '자막';
    chips.add(_MetaChip(label: sourceLabel));

    if (transcript!.partial) {
      chips.add(const _MetaChip(label: '자막 일부'));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}

class _TranscriptBody extends StatelessWidget {
  const _TranscriptBody({
    required this.transcript,
    required this.isLoading,
    required this.onRequestSummary,
  });

  final TranscriptResult? transcript;
  final bool isLoading;
  final VoidCallback onRequestSummary;

  @override
  Widget build(BuildContext context) {
    if (isLoading && transcript == null) {
      return Row(
        children: const [
          CupertinoActivityIndicator(radius: 8),
          SizedBox(width: 8),
          Text(
            '자막/음성 텍스트 생성 중',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      );
    }

    if (transcript != null && transcript!.source == 'error') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            transcript!.text,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: '다시 요약하기',
            onPressed: onRequestSummary,
          ),
        ],
      );
    }

    if (transcript == null || transcript!.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '요약이 아직 생성되지 않았습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: '요약하기',
            onPressed: onRequestSummary,
          ),
        ],
      );
    }

    final summary = (transcript!.summary ?? '').trim();
    final displayText = summary.isNotEmpty ? summary : transcript!.text;

    return Text(
      displayText,
      style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minSize: 32,
      color: AppColors.brand,
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}
