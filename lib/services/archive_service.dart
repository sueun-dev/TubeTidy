import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/archive.dart';
import 'backend_api.dart';

class ArchiveMutationRequest {
  const ArchiveMutationRequest({
    required this.videoId,
    required this.archived,
    this.title,
    this.thumbnailUrl,
    this.channelId,
    this.channelTitle,
    this.channelThumbnailUrl,
  });

  final String videoId;
  final bool archived;
  final String? title;
  final String? thumbnailUrl;
  final String? channelId;
  final String? channelTitle;
  final String? channelThumbnailUrl;
}

class ArchiveToggleResult {
  const ArchiveToggleResult({
    required this.archived,
    this.archivedAt,
    this.entry,
  });

  final bool archived;
  final DateTime? archivedAt;
  final ArchiveEntry? entry;
}

class ArchiveService {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<List<ArchiveEntry>?> fetchArchives(String userId) async {
    if (userId.isEmpty) return null;
    final uri = BackendApi.uri('/archives', queryParameters: {
      'user_id': userId,
    });
    try {
      final response =
          await http.get(uri, headers: BackendApi.headers()).timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      final entries = <ArchiveEntry>[];
      for (final item in items) {
        final videoId = item['video_id'] as String?;
        final archivedAt = item['archived_at'];
        if (videoId == null || archivedAt == null) continue;
        final millis = archivedAt is int
            ? archivedAt
            : int.tryParse(archivedAt.toString());
        if (millis == null) continue;
        entries.add(
          ArchiveEntry(
            videoId: videoId,
            archivedAt: DateTime.fromMillisecondsSinceEpoch(millis),
            title: item['title'] as String?,
            thumbnailUrl: item['thumbnail_url'] as String?,
            channelId: item['channel_id'] as String?,
            channelTitle: item['channel_title'] as String?,
            channelThumbnailUrl: item['channel_thumbnail_url'] as String?,
          ),
        );
      }
      return entries;
    } catch (_) {
      return null;
    }
  }

  static Future<ArchiveToggleResult?> toggleArchive({
    required String userId,
    required ArchiveMutationRequest request,
  }) async {
    if (userId.isEmpty || request.videoId.isEmpty) return null;
    final uri = BackendApi.uri('/archives/toggle');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({
              'user_id': userId,
              'video_id': request.videoId,
              'archived': request.archived,
              'title': request.title,
              'thumbnail_url': request.thumbnailUrl,
              'channel_id': request.channelId,
              'channel_title': request.channelTitle,
              'channel_thumbnail_url': request.channelThumbnailUrl,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final archived = data['archived'] == true;
      final archivedAt = data['archived_at'];
      DateTime? parsed;
      if (archivedAt != null) {
        final millis = archivedAt is int
            ? archivedAt
            : int.tryParse(archivedAt.toString());
        if (millis != null) {
          parsed = DateTime.fromMillisecondsSinceEpoch(millis);
        }
      }
      ArchiveEntry? entry;
      final entryVideoId = data['video_id'] as String?;
      if (entryVideoId != null && parsed != null) {
        entry = ArchiveEntry(
          videoId: entryVideoId,
          archivedAt: parsed,
          title: data['title'] as String?,
          thumbnailUrl: data['thumbnail_url'] as String?,
          channelId: data['channel_id'] as String?,
          channelTitle: data['channel_title'] as String?,
          channelThumbnailUrl: data['channel_thumbnail_url'] as String?,
        );
      }
      return ArchiveToggleResult(
        archived: archived,
        archivedAt: parsed,
        entry: entry,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> clearArchives(String userId) async {
    if (userId.isEmpty) return false;
    final uri = BackendApi.uri('/archives/clear');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
