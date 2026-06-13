import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/core/services/fcm_service.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

final fcmInitProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(authProvider, (previous, next) {
    final prevUser = previous?.asData?.value;
    final nextUser = next.asData?.value;

    if (prevUser == null && nextUser != null) {
      // On web/iOS PWA — skip auto-init. Permission must come from a user tap.
      // The NotificationPermissionBanner in the UI handles this.
      if (kIsWeb) return;

      // Native Android/iOS: auto-init is fine
      FCMService.initFCM().catchError((e) {});
    }

    if (prevUser != null && nextUser == null) {
      FCMService.removeToken().catchError((_) {});
    }
  });
});