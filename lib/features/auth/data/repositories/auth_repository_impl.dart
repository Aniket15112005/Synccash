import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/auth/data/models/user_model.dart';
import 'package:synccash/features/auth/domain/entities/user_entity.dart';
import 'package:synccash/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<UserEntity?> get authStateChanges {
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      if (firebaseUser == null) return Stream.value(null);

      // snapshots() serves from Firestore LOCAL CACHE instantly on first emit,
      // then updates from server — no network wait before cashbookId is available.
      return _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .snapshots()
          .asyncMap((doc) async {
        if (!doc.exists) {
          final fallbackUser = UserModel(
            uid: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName: '',
          );
          await _firestore
              .collection('users')
              .doc(firebaseUser.uid)
              .set(fallbackUser.toJson());
          return fallbackUser as UserEntity?;
        }
        return UserModel.fromJson(doc.data()!) as UserEntity?;
      });
    });
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final credentials = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final doc = await _firestore
        .collection('users')
        .doc(credentials.user!.uid)
        .get();

    // ✅ FIX 2: prevent crash if doc missing
    if (!doc.exists) {
      final newUser = UserModel(
        uid: credentials.user!.uid,
        email: email,
        displayName: '',
      );

      await _firestore
          .collection('users')
          .doc(newUser.uid)
          .set(newUser.toJson());

      return newUser;
    }

    return UserModel.fromJson(doc.data()!);
  }

  @override
  Future<UserEntity> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    final credentials = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final model = UserModel(
      uid: credentials.user!.uid,
      email: email,
      displayName: name,
    );

    await _firestore
        .collection('users')
        .doc(model.uid)
        .set(model.toJson());

    return model;
  }

  @override
  Future<void> signOut() async => await _auth.signOut();

  @override
  Future<void> resetPassword(String email) async =>
      await _auth.sendPasswordResetEmail(email: email);
}