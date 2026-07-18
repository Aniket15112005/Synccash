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
        // Guard: if the snapshot says doc doesn't exist but it came from cache
        // (i.e. Firestore is offline and hasn't confirmed from server yet),
        // do NOT create a fallback user — that would wipe currentCashbookId
        // and send the user to the pairing screen. Return null to keep the
        // router in its loading state until Firestore reconnects.
        if (!doc.exists && doc.metadata.isFromCache) {
          return null;
        }

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

    // Try server first, then fall back to local cache (handles iOS PWA where
    // Firestore's WebChannel is offline during the first login attempt).
    // Without this, the raw .get() throws "client offline", shows an error
    // SnackBar, and the auth state change simultaneously routes the user to
    // the pairing screen with a blank currentCashbookId.
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _firestore
          .collection('users')
          .doc(credentials.user!.uid)
          .get(const GetOptions(source: Source.serverAndCache));
    } catch (_) {
      // Server unreachable — try cache
      try {
        doc = await _firestore
            .collection('users')
            .doc(credentials.user!.uid)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        // No cache either — return a placeholder. The authStateChanges stream
        // will emit the real user document once Firestore reconnects.
        return UserModel(
          uid: credentials.user!.uid,
          email: email,
          displayName: '',
        );
      }
    }

    if (!doc.exists) {
      final newUser = UserModel(
        uid: credentials.user!.uid,
        email: email,
        displayName: '',
      );
      // Queue the write — Firestore will sync once connection resumes
      _firestore
          .collection('users')
          .doc(newUser.uid)
          .set(newUser.toJson())
          .catchError((_) {});
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