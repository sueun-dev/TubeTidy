import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transcript.dart';

class TranscriptCache {
  TranscriptCache(this._prefs);

  static const int cacheVersion = 1;
  static const Duration ttl = Duration(days: 7);

  final SharedPreferences _prefs;

  static Future<TranscriptCache> create() async {
    final prefs = await SharedPreferences.getInstance();
    return TranscriptCache(prefs);
  }

  Future<TranscriptResult?> read({
    required String userId,
    required String videoId,
  }) async {
    final key = _key(userId, videoId);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = data['saved_at'] as int?;
      if (savedAt == null) {
        _prefs.remove(key);
        return null;
      }
      final age = DateTime.now().millisecondsSinceEpoch - savedAt;
      if (age > ttl.inMilliseconds) {
        _prefs.remove(key);
        return null;
      }

      return TranscriptResult(
        text: (data['text'] as String?) ?? '',
        summary: data['summary'] as String?,
        source: (data['source'] as String?) ?? 'captions',
        partial: data['partial'] == true,
      );
    } catch (_) {
      _prefs.remove(key);
      return null;
    }
  }

  Future<void> write({
    required String userId,
    required String videoId,
    required TranscriptResult result,
  }) async {
    final key = _key(userId, videoId);
    final payload = <String, dynamic>{
      'text': result.text,
      'summary': result.summary,
      'source': result.source,
      'partial': result.partial,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    };
    await _prefs.setString(key, jsonEncode(payload));
  }

  Future<void> clearUser(String userId) async {
    final prefix = _prefix(userId);
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(prefix)) {
        await _prefs.remove(key);
      }
    }
  }

  String _prefix(String userId) => 'transcript_cache_v$cacheVersion:$userId:';

  String _key(String userId, String videoId) => '${_prefix(userId)}$videoId';
}
