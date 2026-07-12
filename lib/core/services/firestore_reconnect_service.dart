// lib/core/services/firestore_reconnect_service.dart
//
// Root-cause fix for screens (Bills, Sales, Purchases, etc.) that
// sometimes get stuck forever on the loading spinner.
//
// Cloud Firestore's realtime `.snapshots()` listeners are opened over a
// long-lived connection (WebChannel/long-polling on web, gRPC on mobile).
// When the app/PWA is backgrounded — the phone is locked, the user
// switches apps, or (especially on iOS Safari/PWA) the tab is suspended —
// that connection can be silently left half-open by the OS/browser. No
// error is ever delivered to Flutter in that case. If a StreamProvider
// hadn't received its first snapshot yet when this happens, it just stays
// in `AsyncLoading()` forever once the app comes back to the foreground —
// which matches "sometimes it loads, sometimes it's stuck".
//
// The fix: whenever the app returns to the foreground after having been
// backgrounded, force Firestore to drop and reopen its network connection
// so every active listener gets a fresh stream (and a fresh first
// snapshot) instead of relying on a connection that may already be dead.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class FirestoreReconnectService extends WidgetsBindingObserver {
  FirestoreReconnectService._();
  static final FirestoreReconnectService instance =
      FirestoreReconnectService._();

  bool _started = false;
  bool _wasBackgrounded = false;

  /// Call once, after `Firebase.initializeApp()`.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _wasBackgrounded = true;
      case AppLifecycleState.resumed:
        if (_wasBackgrounded) {
          _wasBackgrounded = false;
          _forceReconnect();
        }
      default:
        break;
    }
  }

  Future<void> _forceReconnect() async {
    try {
      final fs = FirebaseFirestore.instance;
      await fs.disableNetwork();
      await fs.enableNetwork();
    } catch (e) {
      // Best effort only — if this fails the app still works, listeners
      // just fall back to the SDK's own (slower) retry/backoff logic.
      if (kDebugMode) {
        debugPrint('⚠️ FirestoreReconnectService: reconnect failed: $e');
      }
    }
  }
}
