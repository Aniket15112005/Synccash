import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/features/transactions/data/models/transaction_model.dart';

import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

import 'package:synccash/features/transactions/domain/repositories/transaction_repository.dart';



class TransactionRepositoryImpl implements TransactionRepository {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;



  @override

  Future<void> addTransaction(TransactionEntity tx) async {

    try {

      final txRef = _firestore

          .collection('cashbooks')

          .doc(tx.cashbookId)

          .collection('transactions')

          .doc();



      final cashbookRef =

          _firestore.collection('cashbooks').doc(tx.cashbookId);



      final model = TransactionModel(

        transactionId: txRef.id,

        cashbookId: tx.cashbookId,

        createdBy: tx.createdBy,

        creatorName: tx.creatorName,

        createdAt: tx.createdAt,

        amount: tx.amount,

        type: tx.type,

        category: tx.category,

        description: tx.description,

      );



      await _firestore.runTransaction((transaction) async {

        final cashbookSnapshot = await transaction.get(cashbookRef);



        if (!cashbookSnapshot.exists) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' does not exist.",

          );

        }



        final data = cashbookSnapshot.data();



        if (data == null) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' contains no data.",

          );

        }



        final num currentBalance =

            (data['totalBalance'] as num?) ?? 0;



        final num currentIncome =

            (data['totalIncome'] as num?) ?? 0;



        final num currentExpense =

            (data['totalExpense'] as num?) ?? 0;



        transaction.set(txRef, model.toJson());



        final bool isIncome =

            tx.type.toLowerCase().trim() == 'income';



        if (isIncome) {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance + tx.amount,

            'totalIncome': currentIncome + tx.amount,

          });

        } else {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance - tx.amount,

            'totalExpense': currentExpense + tx.amount,

          });

        }

      });

    } on FirebaseException {

      rethrow;

    }

  }



  @override

  Future<void> deleteTransaction(TransactionEntity tx) async {

    try {

      final txRef = _firestore

          .collection('cashbooks')

          .doc(tx.cashbookId)

          .collection('transactions')

          .doc(tx.transactionId);



      final cashbookRef =

          _firestore.collection('cashbooks').doc(tx.cashbookId);



      await _firestore.runTransaction((transaction) async {

        // FIX: all reads must come before any writes in a Firestore transaction
        final txSnapshot = await transaction.get(txRef);

        final cashbookSnapshot = await transaction.get(cashbookRef);



        if (!txSnapshot.exists) {

          throw Exception(

            "Transaction '${tx.transactionId}' does not exist.",

          );

        }



        if (!cashbookSnapshot.exists) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' does not exist.",

          );

        }



        final cashbookData = cashbookSnapshot.data();



        if (cashbookData == null) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' contains no data.",

          );

        }



        final txData = txSnapshot.data()!;

        final num amount = (txData['amount'] as num?) ?? tx.amount;

        final String type = (txData['type'] as String?) ?? tx.type;



        final num currentBalance =

            (cashbookData['totalBalance'] as num?) ?? 0;

        final num currentIncome =

            (cashbookData['totalIncome'] as num?) ?? 0;

        final num currentExpense =

            (cashbookData['totalExpense'] as num?) ?? 0;



        final bool isIncome =

            type.toLowerCase().trim() == 'income';



        if (isIncome) {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance - amount,

            'totalIncome': currentIncome - amount,

          });

        } else {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance + amount,

            'totalExpense': currentExpense - amount,

          });

        }



        transaction.delete(txRef);

      });

    } on FirebaseException {

      rethrow;

    }

  }

  @override
  Future<void> updateTransaction(TransactionEntity tx) async {
    try {
      final txRef = _firestore
          .collection('cashbooks')
          .doc(tx.cashbookId)
          .collection('transactions')
          .doc(tx.transactionId);

      final cashbookRef =
          _firestore.collection('cashbooks').doc(tx.cashbookId);

      await _firestore.runTransaction((transaction) async {
        final txSnapshot = await transaction.get(txRef);
        final cashbookSnapshot = await transaction.get(cashbookRef);

        if (!txSnapshot.exists) {
          throw Exception(
            "Transaction '${tx.transactionId}' does not exist.",
          );
        }

        if (!cashbookSnapshot.exists) {
          throw Exception(
            "Cashbook '${tx.cashbookId}' does not exist.",
          );
        }

        final cashbookData = cashbookSnapshot.data()!;
        final oldData = txSnapshot.data()!;

        final num oldAmount = (oldData['amount'] as num?) ?? tx.amount;
        final String oldType = (oldData['type'] as String?) ?? tx.type;
        final bool wasIncome = oldType.toLowerCase().trim() == 'income';
        final bool isIncome = tx.type.toLowerCase().trim() == 'income';

        num balance = (cashbookData['totalBalance'] as num?) ?? 0;
        num income  = (cashbookData['totalIncome']  as num?) ?? 0;
        num expense = (cashbookData['totalExpense'] as num?) ?? 0;

        // Reverse old amount
        if (wasIncome) {
          balance -= oldAmount;
          income  -= oldAmount;
        } else {
          balance += oldAmount;
          expense -= oldAmount;
        }

        // Apply new amount
        if (isIncome) {
          balance += tx.amount;
          income  += tx.amount;
        } else {
          balance -= tx.amount;
          expense += tx.amount;
        }

          transaction.update(txRef, {
          'amount':       tx.amount,
          'type':         tx.type,
          'category':     tx.category,
          'description':  tx.description,
          'createdAt':    Timestamp.fromDate(tx.createdAt),
          'createdBy':    tx.createdBy,      // ← saves creator change
          'creatorName':  tx.creatorName,    // ← saves creator name change
          'lastEditedBy': tx.lastEditedBy,   // ← correct field name
        });

        transaction.update(cashbookRef, {
          'totalBalance': balance,
          'totalIncome':  income,
          'totalExpense': expense,
        });
      });
    } on FirebaseException {
      rethrow;
    }
  }

  // ── ONLY CHANGE: added `if (limit > 0)` guard so limit:0 fetches ALL records.
  // ── Also removed the duplicate @override that was present in the original.
  @override
  Stream<List<TransactionEntity>> getTransactionsStream(
    String cashbookId, {
    int limit = 5000,
  }) {
    var query = FirebaseFirestore.instance
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .orderBy('createdAt', descending: true);

    if (limit > 0) query = query.limit(limit); // 0 = fetch everything

    return query
        .snapshots()
        .map((snap) => snap.docs
            .map<TransactionEntity>(
                (d) => TransactionModel.fromFirestore(d))
            .toList());
  }

}
