// lib/features/settings/services/backup_frequency_service.dart

import 'package:shared_preferences/shared_preferences.dart';

enum BackupFrequency {
  daily,
  weekly,
  monthly,
  never;

  String get label {
    switch (this) {
      case BackupFrequency.daily:   return 'Every Day';
      case BackupFrequency.weekly:  return 'Every Week';
      case BackupFrequency.monthly: return 'Every Month';
      case BackupFrequency.never:   return 'Never';
    }
  }

  String get subtitle {
    switch (this) {
      case BackupFrequency.daily:   return 'Auto-backup runs once a day';
      case BackupFrequency.weekly:  return 'Auto-backup runs once a week';
      case BackupFrequency.monthly: return 'Auto-backup runs once a month';
      case BackupFrequency.never:   return 'Only back up when you tap manually';
    }
  }
}

class BackupFrequencyService {
  BackupFrequencyService._();

  static const _kFreqKey        = 'backup_frequency';
  static const _kLastBackupKey  = 'last_auto_backup';

  static Future<BackupFrequency> getFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    final val   = prefs.getString(_kFreqKey) ?? 'never';
    return BackupFrequency.values.firstWhere(
      (e) => e.name == val,
      orElse: () => BackupFrequency.never,
    );
  }

  static Future<void> setFrequency(BackupFrequency freq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFreqKey, freq.name);
  }

  /// Returns true if an automatic backup should be triggered right now.
  static Future<bool> isBackupDue() async {
    final freq = await getFrequency();
    if (freq == BackupFrequency.never) return false;

    final prefs   = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_kLastBackupKey);
    if (lastStr == null) return true; // never backed up before

    final last = DateTime.parse(lastStr);
    final now  = DateTime.now();
    final diff = now.difference(last).inDays;

    switch (freq) {
      case BackupFrequency.daily:   return diff >= 1;
      case BackupFrequency.weekly:  return diff >= 7;
      case BackupFrequency.monthly: return diff >= 30;
      case BackupFrequency.never:   return false;
    }
  }

  /// Call this after every successful backup (manual or auto).
  static Future<void> recordBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupKey, DateTime.now().toIso8601String());
  }
}
