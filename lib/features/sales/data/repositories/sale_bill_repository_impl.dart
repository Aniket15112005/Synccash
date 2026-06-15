import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sale_bill_entity.dart';
import '../../domain/repositories/sale_bill_repository.dart';
import '../models/sale_bill_model.dart';

class SaleBillRepositoryImpl implements SaleBillRepository {
  final FirebaseFirestore _firestore;

  SaleBillRepositoryImpl(this._firestore);

  CollectionReference<Map<String, dynamic>> _billsRef(String cashbookId) =>
      _firestore
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills');

  @override
  Stream<List<SaleBillEntity>> watchBills(String cashbookId) {
    return _billsRef(cashbookId)
        .orderBy('billCreatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(SaleBillModel.fromFirestore).toList());
  }

  @override
  Stream<List<SaleBillEntity>> watchPendingBillsByPartyName(
    String cashbookId,
    String query,
  ) {
    final q = query.toLowerCase();
    return _billsRef(cashbookId)
        .where('billStatus', isEqualTo: 'pending')
        .orderBy('billCreatedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map(SaleBillModel.fromFirestore)
            .where((b) => b.partyName.toLowerCase().contains(q))
            .toList());
  }

  @override
  Future<void> addBill(String cashbookId, Map<String, dynamic> data) async {
    final docRef = _billsRef(cashbookId).doc();
    data['saleBillId'] = docRef.id;
    await docRef.set(data);
  }

  @override
  Future<void> settleBill(String cashbookId, String billId) async {
    await _billsRef(cashbookId).doc(billId).update({'billStatus': 'settled'});
  }
}
