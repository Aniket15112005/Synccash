import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/auth/data/models/user_model.dart';
import 'package:synccash/features/auth/domain/entities/user_entity.dart';
import 'package:synccash/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Offline-tolerant retry wrapper ────────────────────────────────────────
  // Right after a fresh iOS PWA login, Firestore's own connection can still
  // be mid-handshake even though Firebase Auth already succeeded (Auth and
  // Firestore use separate connections). A one-shot server read can throw
  // `unavailable` in that window. Retry briefly instead of giving up.
  Future<T> _withRetry<T>(
    Future<T> Function() task, {
    int retries = 4,
    Duration delay = const Duration(milliseconds: 700),
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await task();
      } on FirebaseException catch (e) {
        final retryable = e.code == 'unavailable' || e.code == 'deadline-exceeded';
        if (!retryable || attempt >= retries) rethrow;
        await Future.delayed(delay);
      }
    }
  }

  UserEntity _mapDoc(User firebaseUser, DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) {
      return UserModel(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName: '',
      );
    }
    return UserModel.fromJson(doc.data()!);
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      if (firebaseUser == null) return Stream.value(null);
      return _userDocStream(firebaseUser);
    });
  }

  // ── The actual fix ─────────────────────────────────────────────────────────
  // Never let the router's first-ever decision be based on a guess. Before
  // handing off to the live .snapshots() listener (which can legitimately
  // serve a fast-but-possibly-stale/empty local snapshot first), get ONE
  // authoritative answer straight from the server, retrying through the
  // "connection still waking up" window. Only after that do we start
  // streaming live updates. This is what guarantees the app never shows the
  // pairing screen just because the cache happened to be empty or slow.
  Stream<UserEntity?> _userDocStream(User firebaseUser) async* {
    final ref = _firestore.collection('users').doc(firebaseUser.uid);

    DocumentSnapshot<Map<String, dynamic>>? initial;
    try {
      initial = await _withRetry(
        () => ref.get(const GetOptions(source: Source.server)),
        retries: 6,
        delay: const Duration(milliseconds: 900),
      );
    } catch (_) {
      // Genuinely no network after retrying — fall back to whatever's cached
      // (better than nothing), but this is now a last resort, not the norm.
      try {
        initial = await ref.get(const GetOptions(source: Source.cache));
      } catch (_) {
        // No cache either. Don't emit a guess — stay in the loading state
        // (router keeps showing splash) until the live listener below
        // manages to deliver a real snapshot.
        initial = null;
      }
    }

    if (initial != null) {
      final fromServer = !initial.metadata.isFromCache;

      // If the confirmed server doc doesn't exist yet, create it now so
      // later reads (and other devices) see a consistent record.
      if (!initial.exists) {
        if (fromServer) {
          final fallbackUser = UserModel(
            uid: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName: '',
          );
          _withRetry(() => ref.set(fallbackUser.toJson())).catchError((_) {});
          yield fallbackUser;
        }
        // Cache says "doesn't exist" — ambiguous (could just be an
        // uncached brand-new tab). Don't create/overwrite anything from
        // a guess; wait for the live listener below to confirm.
      } else {
        final mapped = _mapDoc(firebaseUser, initial);
        // A cache-sourced doc that already shows a cashbook is safe to
        // trust immediately (positive info). A cache-sourced doc showing
        // NO cashbook is ambiguous — it may just predate pairing — so
        // don't act on it. Stay in "loading" (router keeps showing the
        // splash a moment longer) until the live listener below delivers
        // a real, server-confirmed snapshot. This is what stops an
        // already-paired user from ever flashing the pairing screen.
        if (mapped.currentCashbookId != null || fromServer) {
          yield mapped;
        }
      }
    }

    // From here on, stream live updates as normal. Any individual snapshot
    // that's a cache-only "doesn't exist" is ignored — we've already
    // established the authoritative truth above, so a stale/offline blip
    // shouldn't override it.
    // Skip any snapshot that comes from local cache — we already have the
    // authoritative server answer from the read above. Trusting a stale
    // cached doc here (e.g. one saved before the user paired a cashbook)
    // can otherwise briefly bounce a correctly-paired user to the pairing
    // screen before the real server update catches up. Only server-
    // confirmed updates are allowed to change the auth state from here on.
    yield* ref.snapshots().where((doc) {
      if (doc.metadata.isFromCache) return false;
      return true;
    }).map((doc) => _mapDoc(firebaseUser, doc));
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final credentials = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // This return value is only used by the login screen to know the sign-in
    // call itself succeeded — actual navigation happens via authStateChanges
    // above, which now handles the offline/cache-timing race correctly. We
    // still try to give back real data here on a best-effort basis.
    try {
      final doc = await _withRetry(() => _firestore
          .collection('users')
          .doc(credentials.user!.uid)
          .get(const GetOptions(source: Source.server)));
      return _mapDoc(credentials.user!, doc);
    } catch (_) {
      return UserModel(
        uid: credentials.user!.uid,
        email: email,
        displayName: '',
      );
    }
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

    await _withRetry(() => _firestore
        .collection('users')
        .doc(model.uid)
        .set(model.toJson()));

    return model;
  }

  @override
  Future<void> signOut() async => await _auth.signOut();

  @override
  Future<void> resetPassword(String email) async =>
      await _auth.sendPasswordResetEmail(email: email);
}