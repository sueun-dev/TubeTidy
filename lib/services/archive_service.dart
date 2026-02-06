import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/archive.dart';
import 'backend_api.dart';

class ArchiveToggleResult {
  const ArchiveToggleResult({required this.archived, this.archivedAt});

  final bool archived;
  final DateTime? archivedAt;
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
          ),
        );
      }
      return entries;
    } catch (_) {
      return null;
    }
  }

  static Future<ArchiveToggleResult?> toggleArchive(
    String userId,
    String videoId,
  ) async {
    if (userId.isEmpty || videoId.isEmpty) return null;
    final uri = BackendApi.uri('/archives/toggle');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({'user_id': userId, 'video_id': videoId}),
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
      return ArchiveToggleResult(archived: archived, archivedAt: parsed);
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
