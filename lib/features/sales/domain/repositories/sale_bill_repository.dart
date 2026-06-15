import '../entities/sale_bill_entity.dart';

abstract class SaleBillRepository {
  Stream<List<SaleBillEntity>> watchBills(String cashbookId);
  Stream<List<SaleBillEntity>> watchPendingBillsByPartyName(
    String cashbookId,
    String query,
  );
  Future<void> addBill(String cashbookId, Map<String, dynamic> data);
  Future<void> settleBill(String cashbookId, String billId);
}
