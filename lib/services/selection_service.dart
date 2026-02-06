import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'backend_api.dart';

class SelectionService {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<Set<String>?> fetchSelection(String userId) async {
    if (userId.isEmpty) return null;
    final uri =
        BackendApi.uri('/selection', queryParameters: {'user_id': userId});
    try {
      final response =
          await http.get(uri, headers: BackendApi.headers()).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['selected_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      return items;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) async {
    if (userId.isEmpty) return false;
    final uri = BackendApi.uri('/selection');
    final normalizedSelected = selectedIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final selectedSet = normalizedSelected.toSet();
    final payloadChannels = channels
        .where((channel) => selectedSet.contains(channel.id))
        .map(
          (channel) => {
            'id': channel.id,
            'title': channel.title,
            'thumbnail_url': channel.thumbnailUrl,
          },
        )
        .toList();
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({
              'user_id': userId,
              'channels': payloadChannels,
              'selected_ids': normalizedSelected,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
