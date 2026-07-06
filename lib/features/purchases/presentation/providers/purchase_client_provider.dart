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

  Future<void> deleteClient(String cashbookId, String clientName) async {
    await _col(cashbookId).doc(clientName.toLowerCase()).delete();
  }
}

final purchaseClientRepositoryProvider =
    Provider<PurchaseClientRepository>((ref) => PurchaseClientRepository());

/// Streams all saved purchase clients for the active cashbook.
final purchaseClientsProvider =
    StreamProvider.autoDispose<List<PurchaseClientEntity>>((ref) {
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
