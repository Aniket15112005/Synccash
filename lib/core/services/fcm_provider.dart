import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/core/services/fcm_service.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

// This provider watches the auth state and initializes FCM exactly once
// after the user logs in. It is kept alive by being watched from app.dart.
// When the user logs out, FCM token is removed automatically.
final fcmInitProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(authProvider, (previous, next) {
    final prevUser = previous?.asData?.value;
    final nextUser = next.asData?.value;

    if (prevUser == null && nextUser != null) {
      // User just logged in — initialize FCM
      FCMService.initFCM().catchError((e) {
        // Non-fatal: app works without push notifications
      });
    }

    if (prevUser != null && nextUser == null) {
      // User just logged out — clean up FCM token
      FCMService.removeToken().catchError((_) {});
    }
  });
});