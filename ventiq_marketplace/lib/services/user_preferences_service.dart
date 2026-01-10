import 'package:shared_preferences/shared_preferences.dart';

enum NotificationConsentStatus {
  accepted('aceptado'),
  denied('denegado'),
  remindLater('mas_tarde'),
  never('nunca');

  final String value;
  const NotificationConsentStatus(this.value);

  static NotificationConsentStatus? fromValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final status in NotificationConsentStatus.values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

class UserPreferencesService {
  static const String _appVersionKey = 'app_version_marketplace';

  static const String _lastUpdateDialogShownKey =
      'last_update_dialog_shown_marketplace';
  static const int _updateDialogIntervalHours = 3;

  static const String _notificationConsentStatusKey =
      'notification_consent_status_marketplace';
  static const String _notificationConsentUpdatedAtKey =
      'notification_consent_updated_at_marketplace';
  static const String _notificationConsentPromptLastShownAtKey =
      'notification_consent_prompt_last_shown_at_marketplace';
  static const int _notificationRemindLaterIntervalHours = 24;

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

  Future<NotificationConsentStatus?> getNotificationConsentStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_notificationConsentStatusKey);
      return NotificationConsentStatus.fromValue(raw);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> getNotificationConsentUpdatedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getInt(_notificationConsentUpdatedAtKey);
      if (raw == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> setNotificationConsentStatus(
    NotificationConsentStatus status, {
    DateTime? updatedAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_notificationConsentStatusKey, status.value);
      await prefs.setInt(
        _notificationConsentUpdatedAtKey,
        (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> markNotificationConsentPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _notificationConsentPromptLastShownAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<bool> shouldShowNotificationConsentPrompt() async {
    try {
      final status = await getNotificationConsentStatus();
      if (status == NotificationConsentStatus.accepted) return false;
      if (status == NotificationConsentStatus.never) return false;
      if (status == NotificationConsentStatus.denied) return false;

      if (status == null) return true;

      if (status == NotificationConsentStatus.remindLater) {
        final prefs = await SharedPreferences.getInstance();
        final lastShown = prefs.getInt(
          _notificationConsentPromptLastShownAtKey,
        );
        if (lastShown == null) return true;
        final lastShownTime = DateTime.fromMillisecondsSinceEpoch(lastShown);
        final diff = DateTime.now().difference(lastShownTime);
        return diff.inHours >= _notificationRemindLaterIntervalHours;
      }

      return true;
    } catch (_) {
      return true;
    }
  }
}
