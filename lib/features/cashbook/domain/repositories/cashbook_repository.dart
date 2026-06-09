import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';

abstract class CashbookRepository {
  Future<CashbookEntity> createCashbook(String userId);
  Future<CashbookEntity> joinCashbook(String userId, String inviteCode);
  Stream<CashbookEntity> watchCashbook(String cashbookId);
}