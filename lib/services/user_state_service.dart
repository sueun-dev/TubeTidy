import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_api.dart';

class UserStatePayload {
  const UserStatePayload({
    required this.selectionChangeDay,
    required this.selectionChangesToday,
    required this.openedVideoIds,
  });

  final int selectionChangeDay;
  final int selectionChangesToday;
  final List<String> openedVideoIds;
}

class UserStateService {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<UserStatePayload?> fetchState(String userId) async {
    if (userId.isEmpty) return null;
    final uri =
        BackendApi.uri('/user/state', queryParameters: {'user_id': userId});
    try {
      final response =
          await http.get(uri, headers: BackendApi.headers()).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UserStatePayload(
        selectionChangeDay: _toNonNegativeInt(data['selection_change_day']),
        selectionChangesToday:
            _toNonNegativeInt(data['selection_changes_today']),
        openedVideoIds: _normalizeVideoIds(data['opened_video_ids']),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveState({
    required String userId,
    required int selectionChangeDay,
    required int selectionChangesToday,
    required List<String> openedVideoIds,
  }) async {
    if (userId.isEmpty) return false;
    final uri = BackendApi.uri('/user/state');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({
              'user_id': userId,
              'selection_change_day': selectionChangeDay,
              'selection_changes_today': selectionChangesToday,
              'opened_video_ids': _normalizeVideoIds(openedVideoIds),
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static int _toNonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value.toString());
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  static List<String> _normalizeVideoIds(Object? raw) {
    final source = raw is List ? raw : const [];
    final seen = <String>{};
    final normalized = <String>[];
    for (final item in source) {
      final videoId = item.toString().trim();
      if (videoId.isEmpty) continue;
      if (!seen.add(videoId)) continue;
      normalized.add(videoId);
      if (normalized.length >= 500) break;
    }
    return normalized;
  }
}
