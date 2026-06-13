import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synccash/core/services/fcm_service.dart';

class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> {
  bool _show = false;

  static const _prefKey = 'notif_banner_dismissed';

  @override
  void initState() {
    super.initState();
    // Only show on web/PWA
    if (!kIsWeb) return;
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final prefs     = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_prefKey) ?? false;
    if (dismissed) return;

    // Don't show if already granted
    final alreadyGranted = await _isPermissionGranted();
    if (alreadyGranted) return;

    if (mounted) setState(() => _show = true);
  }

  Future<bool> _isPermissionGranted() async {
    // Check JS Notification.permission
    try {
      // Reuse the web shim — if permission is 'granted' we're done
      return false; // default: assume not granted, let FCMService handle check
    } catch (_) {
      return false;
    }
  }

  Future<void> _onEnable() async {
    setState(() => _show = false);
    // This tap IS the user gesture — iOS will show the permission prompt now
    await FCMService.initFCM();
  }

  Future<void> _onDismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: const Text(
        'Enable notifications to get alerted when your partner adds or edits entries.',
        style: TextStyle(fontSize: 13),
      ),
      leading: const Icon(Icons.notifications_outlined),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      actions: [
        TextButton(
          onPressed: _onDismiss,
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _onEnable,
          child: const Text('Enable'),
        ),
      ],
    );
  }
}