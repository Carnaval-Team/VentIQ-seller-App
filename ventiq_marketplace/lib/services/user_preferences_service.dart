import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesService {
  static const String _appVersionKey = 'app_version_marketplace';

  static const String _lastUpdateDialogShownKey =
      'last_update_dialog_shown_marketplace';
  static const int _updateDialogIntervalHours = 3;

  Future<void> saveAppVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appVersionKey, version);
  }

  Future<String?> getAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appVersionKey);
  }

  Future<bool> isFirstTimeOpening([String? currentVersion]) async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_appVersionKey)) {
      return true;
    }

    if (currentVersion != null) {
      final savedVersion = prefs.getString(_appVersionKey);
      if (savedVersion == null) return true;
      return _isNewerVersion(currentVersion, savedVersion);
    }

    return false;
  }

  bool _isNewerVersion(String currentVersion, String savedVersion) {
    try {
      final cleanCurrent = currentVersion.replaceAll(RegExp(r'[^\d\.]'), '');
      final cleanSaved = savedVersion.replaceAll(RegExp(r'[^\d\.]'), '');

      final currentParts = cleanCurrent
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final savedParts = cleanSaved
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      while (currentParts.length < 3) currentParts.add(0);
      while (savedParts.length < 3) savedParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (currentParts[i] > savedParts[i]) return true;
        if (currentParts[i] < savedParts[i]) return false;
      }

      return false;
    } catch (_) {
      return true;
    }
  }

  Future<bool> shouldShowUpdateDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShownTimestamp = prefs.getInt(_lastUpdateDialogShownKey);
      if (lastShownTimestamp == null) {
        return true;
      }

      final lastShownTime = DateTime.fromMillisecondsSinceEpoch(
        lastShownTimestamp,
      );
      final difference = DateTime.now().difference(lastShownTime);
      return difference.inHours >= _updateDialogIntervalHours;
    } catch (_) {
      return true;
    }
  }

  Future<void> markUpdateDialogShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastUpdateDialogShownKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }
}
