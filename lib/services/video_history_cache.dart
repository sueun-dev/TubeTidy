import 'package:shared_preferences/shared_preferences.dart';

class VideoHistoryCache {
  VideoHistoryCache._(this._prefs);

  final SharedPreferences _prefs;

  static const int cacheVersion = 1;

  static Future<VideoHistoryCache> create() async {
    final prefs = await SharedPreferences.getInstance();
    return VideoHistoryCache._(prefs);
  }

  String _key(String userId) => 'video_history_v$cacheVersion:$userId';

  Future<Set<String>> read(String userId) async {
    final list = _prefs.getStringList(_key(userId));
    if (list == null) return <String>{};
    return list.toSet();
  }

  Future<void> write(String userId, Set<String> videoIds) async {
    await _prefs.setStringList(_key(userId), videoIds.toList());
  }

  Future<void> add(String userId, String videoId) async {
    final updated = await read(userId);
    updated.add(videoId);
    await write(userId, updated);
  }

  Future<void> clear(String userId) async {
    await _prefs.remove(_key(userId));
  }
}
