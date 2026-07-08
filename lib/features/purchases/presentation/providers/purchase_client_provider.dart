// lib/features/purchases/presentation/providers/purchase_client_provider.dart
//
// Mirrors lib/features/sales/presentation/providers/party_provider.dart
// Firestore layout: cashbooks/{cashbookId}/purchase_clients/{clientNameLower}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;

class PurchaseClientEntity {
  final String clientId; // lower-cased client name, doc id
  final String clientName;
  final double openingBalance;
  final String? description;

  const PurchaseClientEntity({
    required this.clientId,
    required this.clientName,
    required this.openingBalance,
    this.description,
  });

  factory PurchaseClientEntity.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PurchaseClientEntity(
      clientId: doc.id,
      clientName: data['clientName'] as String? ?? doc.id,
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0.0,
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'clientName': clientName,
        'openingBalance': openingBalance,
        if (description != null) 'description': description,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class PurchaseClientRepository {
  final FirebaseFirestore _db;
  PurchaseClientRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference _col(String cashbookId) => _db
      .collection('cashbooks')
      .doc(cashbookId)
      .collection('purchase_clients');

  Stream<List<PurchaseClientEntity>> watchClients(String cashbookId) {
    return _col(cashbookId).snapshots().map((snap) => snap.docs
        .map((d) => PurchaseClientEntity.fromFirestore(d))
        .toList()
      ..sort((a, b) =>
          a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase())));
  }

  Future<PurchaseClientEntity?> getClient(
      String cashbookId, String clientName) async {
    final doc = await _col(cashbookId).doc(clientName.toLowerCase()).get();
    if (!doc.exists) return null;
    return PurchaseClientEntity.fromFirestore(doc);
  }

  /// Creates the client doc if it doesn't already exist. Never overwrites an
  /// existing opening balance — safe to call every time a bill is added for
  /// a (possibly new) client name.
  Future<void> ensureClientExists(String cashbookId, String clientName,
      {String? description}) async {
    final ref = _col(cashbookId).doc(clientName.toLowerCase());
    final doc = await ref.get();
    if (doc.exists) return;
    await ref.set(PurchaseClientEntity(
      clientId: clientName.toLowerCase(),
      clientName: clientName,
      openingBalance: 0,
      description: description,
    ).toFirestore());
  }

  Future<void> setOpeningBalance(
      String cashbookId, String clientName, double openingBalance) async {
    await _col(cashbookId).doc(clientName.toLowerCase()).set({
      'clientName': clientName,
      'openingBalance': openingBalance,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> renameClient(
      String cashbookId, String oldName, String newName) async {
    final oldNameTrimmed = oldName.trim();
    final newNameTrimmed = newName.trim();
    final oldId = oldNameTrimmed.toLowerCase();
    final newId = newNameTrimmed.toLowerCase();

    if (oldId == newId) {
      // Same normalized key — only update the display label.
      await _col(cashbookId).doc(oldId).update({
        'clientName': newNameTrimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    // Guard: refuse to overwrite an existing client with a different name.
    final targetDoc = await _col(cashbookId).doc(newId).get();
    if (targetDoc.exists) {
      throw Exception(
          'A client named "$newNameTrimmed" already exists. '
          'Please choose a different name.');
    }

    final cashRef = _db.collection('cashbooks').doc(cashbookId);

    // Read old client document.
    final oldDoc = await _col(cashbookId).doc(oldId).get();
    final oldData = (oldDoc.data() as Map<String, dynamic>?) ?? {};

    // Read all bills that reference oldName (case-sensitive — stored consistently
    // via ensureClientExists). Collect both variants in case of legacy mixed case.
    final billsSnap = await cashRef
        .collection('purchase_bills')
        .where('clientName', isEqualTo: oldNameTrimmed)
        .get();

    // Read expense transactions whose obPartyName matches this client.
    final txSnap = await cashRef
        .collection('transactions')
        .where('isObPayment', isEqualTo: true)
        .where('obPartyName', isEqualTo: oldNameTrimmed)
        .get();

    // --- Chunked batch writes (Firestore limit: 500 ops/batch) ---------------
    // Ops per chunk: 1 create-client + 1 delete-client = 2 fixed ops;
    // remaining 498 slots shared by bill + tx updates.
    const maxOpsPerBatch = 498;

    Future<void> commitChunked(List<DocumentSnapshot> docs,
        Map<String, dynamic> updateData) async {
      for (var i = 0; i < docs.length; i += maxOpsPerBatch) {
        final chunk = docs.sublist(
            i, (i + maxOpsPerBatch).clamp(0, docs.length));
        final b = _db.batch();
        for (final d in chunk) {
          b.update(d.reference, updateData);
        }
        await b.commit();
      }
    }

    // 1. Create the new client doc (carries over openingBalance & other data).
    final clientBatch = _db.batch();
    clientBatch.set(_col(cashbookId).doc(newId), {
      ...oldData,
      'clientName': newNameTrimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    clientBatch.delete(_col(cashbookId).doc(oldId));
    await clientBatch.commit();

    // 2. Rename clientName on all bills (chunked).
    await commitChunked(
        billsSnap.docs, {'clientName': newNameTrimmed});

    // 3. Rename obPartyName on OB-payment transactions (chunked).
    await commitChunked(
        txSnap.docs, {'obPartyName': newNameTrimmed});
  }

  Future<void> deleteClient(String cashbookId, String clientName) async {
    await _col(cashbookId).doc(clientName.toLowerCase()).delete();
  }
}

final purchaseClientRepositoryProvider =
    Provider<PurchaseClientRepository>((ref) => PurchaseClientRepository());

/// Streams all saved purchase clients for the active cashbook.
///
/// FIX (Android party-picker loading delay): this used to be
/// StreamProvider.autoDispose, which meant the underlying Firestore
/// listener was torn down the instant nothing was watching it (i.e. right
/// after _resolveAllPartyNames() finished its one-off `.future` read on the
/// Add Transaction screen). The next time the picker opened, this stream
/// had to reconnect to Firestore from scratch — negotiate a fresh
/// gRPC/HTTP2 channel, re-auth, then wait for the first snapshot. Android's
/// Firestore SDK is consistently slower than iOS's to complete that cold
/// channel setup (a well-known cross-platform gap, not an app bug), which is
/// exactly the ~2s "Loading suggestions…" spinner reported on Android while
/// iOS opened instantly. Removing autoDispose keeps this stream's
/// connection alive for the app's lifetime after first use, so subsequent
/// picker opens read an already-warm cached value instantly on both
/// platforms — matching partiesProvider/allSaleBillsProvider, which never
/// had this problem because they were already non-autoDispose.
final purchaseClientsProvider =
    StreamProvider<List<PurchaseClientEntity>>((ref) {
  final cashbookId = ref.watch(currentCashbookIdProvider);
  if (cashbookId == null) return const Stream.empty();
  return ref.read(purchaseClientRepositoryProvider).watchClients(cashbookId);
});

/// Search query for the Purchases screen.
class PurchaseClientSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void update(String query) => state = query;
}

final purchaseClientSearchProvider =
    NotifierProvider<PurchaseClientSearchNotifier, String>(
  PurchaseClientSearchNotifier.new,
);

/// Filtered + sorted client list driven by [purchaseClientSearchProvider].
final filteredPurchaseClientsProvider =
    Provider.autoDispose<List<PurchaseClientEntity>>((ref) {
  final clients = ref.watch(purchaseClientsProvider).asData?.value ?? [];
  final query = ref.watch(purchaseClientSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return clients;
  return clients
      .where((c) => c.clientName.toLowerCase().contains(query))
      .toList();
});

class PurchaseClientActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> setOpeningBalance(
      String cashbookId, String clientName, double amount) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(purchaseClientRepositoryProvider)
        .setOpeningBalance(cashbookId, clientName, amount));
  }

  Future<void> renameClient(
      String cashbookId, String oldName, String newName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(purchaseClientRepositoryProvider)
        .renameClient(cashbookId, oldName, newName));
  }

  Future<void> deleteClient(String cashbookId, String clientName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(purchaseClientRepositoryProvider)
        .deleteClient(cashbookId, clientName));
  }
}

final purchaseClientActionsProvider =
    AsyncNotifierProvider<PurchaseClientActionsNotifier, void>(
  PurchaseClientActionsNotifier.new,
);
