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
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      final doc = await _firestore.collection('users').doc(firebaseUser.uid).get();
      if (!doc.exists) return null;
      return UserModel.fromJson(doc.data()!);
    });
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final credentials = await _auth.signInWithEmailAndPassword(email: email, password: password);
    final doc = await _firestore.collection('users').doc(credentials.user!.uid).get();
    return UserModel.fromJson(doc.data()!);
  }

  @override
  Future<UserEntity> signUpWithEmail(String email, String password, String name) async {
    final credentials = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final model = UserModel(uid: credentials.user!.uid, email: email, displayName: name);
    await _firestore.collection('users').doc(model.uid).set(model.toJson());
    return model;
  }

  @override
  Future<void> signOut() async => await _auth.signOut();

  @override
  Future<void> resetPassword(String email) async => await _auth.sendPasswordResetEmail(email: email);
}