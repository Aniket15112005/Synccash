// lib/features/daily/domain/repositories/daily_repository.dart

import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';

abstract class DailyRepository {
  Future<void> addEntry(DailyEntryEntity entry);
  Future<void> updateEntry(DailyEntryEntity entry);
  Future<void> deleteEntry(DailyEntryEntity entry);

  /// limit: 0 fetches every entry (no `.limit()` clause applied).
  Stream<List<DailyEntryEntity>> getEntriesStream(String cashbookId,
      {int limit = 0});
}
