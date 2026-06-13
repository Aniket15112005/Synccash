import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/core/services/fcm_service.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';

final fcmInitProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(authProvider, (previous, next) {
    final prevUser = previous?.asData?.value;
    final nextUser = next.asData?.value;

    if (prevUser == null && nextUser != null) {
      // Auto-init on all platforms including iOS PWA.
      // On iOS PWA the OS will show the system permission dialog.
      FCMService.initFCM().catchError((e) {});
    }

    if (prevUser != null && nextUser == null) {
      FCMService.removeToken().catchError((_) {});
    }
  });
});