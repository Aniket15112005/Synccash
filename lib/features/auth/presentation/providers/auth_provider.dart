import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:synccash/features/auth/domain/entities/user_entity.dart';
import 'package:synccash/features/auth/domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

final authProvider = StreamProvider<UserEntity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});