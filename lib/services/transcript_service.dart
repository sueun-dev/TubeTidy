import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transcript.dart';
import 'backend_api.dart';

class TranscriptService {
  static const Duration _timeout = Duration(seconds: 30);

  static Future<TranscriptResult?> fetchTranscript(String videoId) async {
    final uri = BackendApi.uri('/transcript');

    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({
              'video_id': videoId,
              'max_chars': 1200,
              'summarize': true,
              'summary_lines': 3,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final message = _parseErrorMessage(response.body);
        if (message != null && message.trim().isNotEmpty) {
          return TranscriptResult(
            text: message.trim(),
            source: 'error',
            partial: false,
          );
        }
        return const TranscriptResult(
          text: '요약 서버 응답이 실패했습니다. 잠시 후 다시 시도해주세요.',
          source: 'error',
          partial: false,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (data['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return null;

      return TranscriptResult(
        text: text,
        summary: (data['summary'] as String?)?.trim(),
        source: (data['source'] as String?) ?? 'captions',
        partial: data['partial'] == true,
      );
    } catch (_) {
      return const TranscriptResult(
        text: '요약 서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인해주세요.',
        source: 'error',
        partial: false,
      );
    }
  }

  static String? _parseErrorMessage(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is String) {
        final lowered = detail.toLowerCase();
        if (lowered.contains('member') || lowered.contains('membership')) {
          return 'You might not have membership for this video.';
        }
        return detail;
      }
    } catch (_) {}
    return null;
  }
}
