import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:synccash/features/auth/domain/entities/user_entity.dart';
import 'package:synccash/features/auth/domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

final authProvider = StreamProvider<UserEntity?>((ref) {
  return ref.read(authRepositoryProvider).authStateChanges;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authProvider.select((async) => async.asData?.value?.uid),
  );
});

final currentCashbookIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authProvider.select((async) => async.asData?.value?.currentCashbookId),
  );
});