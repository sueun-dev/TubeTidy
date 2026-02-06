import 'package:shared_preferences/shared_preferences.dart';

class SelectionChangeCache {
  SelectionChangeCache(this._prefs);

  static const int cacheVersion = 1;

  final SharedPreferences _prefs;

  static Future<SelectionChangeCache> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SelectionChangeCache(prefs);
  }

  Future<SelectionChangeState?> read(String userId) async {
    final key = _key(userId);
    final raw = _prefs.getStringList(key);
    if (raw == null || raw.length < 2) return null;
    final day = int.tryParse(raw[0]);
    final count = int.tryParse(raw[1]);
    if (day == null || count == null) return null;
    return SelectionChangeState(dayKey: day, changesToday: count);
  }

  Future<void> write(String userId, SelectionChangeState state) async {
    final key = _key(userId);
    await _prefs.setStringList(
      key,
      [state.dayKey.toString(), state.changesToday.toString()],
    );
  }

  Future<void> clear(String userId) async {
    await _prefs.remove(_key(userId));
  }

  String _key(String userId) => 'selection_change_v$cacheVersion:$userId';
}

class SelectionChangeState {
  const SelectionChangeState(
      {required this.dayKey, required this.changesToday});

  final int dayKey;
  final int changesToday;
}
