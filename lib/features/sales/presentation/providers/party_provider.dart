import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;

// ── Entity ────────────────────────────────────────────────────────────────────

class PartyEntity {
  final String partyId;
  final String partyName;
  final double openingBalance;
  final String description;
  final String place;

  const PartyEntity({
    required this.partyId,
    required this.partyName,
    required this.openingBalance,
    this.description = '',
    this.place = '',
  });

  static PartyEntity fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PartyEntity(
      partyId: doc.id,
      partyName: d['partyName'] as String? ?? '',
      openingBalance: (d['openingBalance'] as num?)?.toDouble() ?? 0.0,
      description: d['description'] as String? ?? '',
      place: d['place'] as String? ?? '',
    );
  }

  static PartyEntity nameOnly(String name) => PartyEntity(
        partyId: name.trim().toLowerCase(),
        partyName: name.trim(),
        openingBalance: 0.0,
      );
}

// ── Repository ────────────────────────────────────────────────────────────────

class PartyRepository {
  final FirebaseFirestore _db;
  PartyRepository(this._db);

  CollectionReference<Map<String, dynamic>> _ref(String cashbookId) =>
      _db.collection('cashbooks').doc(cashbookId).collection('parties');

  // Note: No orderBy — sorts in Dart to avoid requiring a Firestore composite
  // index that may not exist. This is functionally identical for our use case.
  Stream<List<PartyEntity>> watchParties(String cashbookId) =>
      _ref(cashbookId).snapshots().map(
            (s) {
              final list = s.docs.map(PartyEntity.fromDoc).toList();
              list.sort((a, b) =>
                  a.partyName.toLowerCase().compareTo(b.partyName.toLowerCase()));
              return list;
            },
          );

  Future<void> saveParty({
    required String cashbookId,
    required String partyName,
    required double openingBalance,
    String description = '',
    String place = '',
  }) =>
      _ref(cashbookId).doc(partyName.trim().toLowerCase()).set({
        'partyName': partyName.trim(),
        'openingBalance': openingBalance,
        'description': description.trim(),
        'place': place.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> deleteParty({
    required String cashbookId,
    required String partyId,
  }) =>
      _ref(cashbookId).doc(partyId).delete();
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _partyRepoProvider =
    Provider((ref) => PartyRepository(FirebaseFirestore.instance));

final partiesProvider =
    StreamProvider<List<PartyEntity>>((ref) {
  final id = ref.watch(currentCashbookIdProvider);
  if (id == null || id.isEmpty) return Stream.value([]);
  return ref.watch(_partyRepoProvider).watchParties(id);
});

class PartyActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveParty({
    required String cashbookId,
    required String partyName,
    required double openingBalance,
    String description = '',
    String place = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(_partyRepoProvider).saveParty(
          cashbookId: cashbookId,
          partyName: partyName,
          openingBalance: openingBalance,
          description: description,
          place: place,
        ));
  }

  Future<void> deleteParty({
    required String cashbookId,
    required String partyId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(_partyRepoProvider).deleteParty(
              cashbookId: cashbookId,
              partyId: partyId,
            ));
  }
}

final partyActionsProvider =
    AsyncNotifierProvider<PartyActionsNotifier, void>(PartyActionsNotifier.new);
