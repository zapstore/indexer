import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'time_utils.dart';

class DatabasePaths {
  static String dataDir() {
    return '${Directory.current.path}/data';
  }

  static String dbPath() {
    return '${dataDir()}/indexer.db';
  }
}

class IndexerDatabase {
  final Database db;

  IndexerDatabase._(this.db);

  static IndexerDatabase openOrCreate() {
    final String dir = DatabasePaths.dataDir();
    Directory(dir).createSync(recursive: true);
    final String path = DatabasePaths.dbPath();
    final Database database = sqlite3.open(path);
    _migrate(database);
    return IndexerDatabase._(database);
  }

  static void _migrate(Database database) {
    database.execute('''
      PRAGMA journal_mode = WAL;
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS apps (
        id TEXT PRIMARY KEY,
        yaml TEXT NOT NULL,
        last_run TEXT,
        interval INTEGER,
        last_error TEXT,
        comments TEXT
      );
    ''');
  }

  void close() {
    db.dispose();
  }

  bool idExists(String id) {
    final ResultSet rs = db.select('SELECT 1 FROM apps WHERE id = ? LIMIT 1', [
      id.toLowerCase(),
    ]);
    return rs.isNotEmpty;
  }

  void deleteById(String id) {
    db.execute('DELETE FROM apps WHERE id = ?', [id.toLowerCase()]);
  }

  void insertIfAbsent({
    required String id,
    required String yaml,
    required DateTime lastRunUtc,
    required DateTime nextRunUtc,
    required int interval,
    String? comments,
  }) {
    // Deprecated: next_run no longer used. Implemented by upsertAppPreserveIntervalOnly.
    upsertAppPreserveIntervalOnly(
      id: id,
      yaml: yaml,
      defaultLastRunUtc: lastRunUtc,
      defaultInterval: interval,
      comments: comments,
    );
  }

  void upsertAppPreserveSchedule({
    required String id,
    required String yaml,
    required DateTime defaultLastRunUtc,
    required DateTime defaultNextRunUtc,
    required int defaultInterval,
    String? comments,
  }) {
    // Deprecated: next_run no longer used.
    upsertAppPreserveIntervalOnly(
      id: id,
      yaml: yaml,
      defaultLastRunUtc: defaultLastRunUtc,
      defaultInterval: defaultInterval,
      comments: comments,
    );
  }

  void upsertAppPreserveIntervalOnly({
    required String id,
    required String yaml,
    required DateTime defaultLastRunUtc,
    required int defaultInterval,
    String? comments,
  }) {
    final String lastIso = TimeUtils.formatMinuteUtc(defaultLastRunUtc);
    db.execute(
      '''
      INSERT INTO apps (id, yaml, last_run, interval, last_error, comments)
      VALUES (?, ?, ?, ?, NULL, ?)
      ON CONFLICT(id) DO UPDATE SET
        yaml = excluded.yaml,
        last_run = COALESCE(last_run, excluded.last_run),
        interval = COALESCE(interval, excluded.interval),
        comments = COALESCE(comments, excluded.comments)
    ''',
      [id.toLowerCase(), yaml, lastIso, defaultInterval, comments],
    );
  }

  // Removed: advanceAllPastDue (next_run removed)

  int removeAppsByRepositoryList(Set<String> repositories) {
    if (repositories.isEmpty) return 0;
    final Set<String> reposLower = repositories
        .map((e) => e.toLowerCase())
        .toSet();
    final ResultSet rs = db.select('SELECT id, yaml FROM apps');
    final List<String> idsToDelete = <String>[];
    for (final Row row in rs) {
      final String id = row['id'] as String;
      final String yaml = (row['yaml'] as String).toLowerCase();
      bool match = false;
      for (final String repo in reposLower) {
        if (yaml.contains(repo)) {
          match = true;
          break;
        }
      }
      if (match) {
        idsToDelete.add(id);
      }
    }
    if (idsToDelete.isEmpty) return 0;
    db.execute('BEGIN');
    try {
      for (final String id in idsToDelete) {
        db.execute('DELETE FROM apps WHERE id = ?', [id]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return idsToDelete.length;
  }

  // Removed: earliestNextRunOnOrAfter (next_run removed)

  // Removed: appsAtExactMinute (next_run removed)

  // Removed: appsInMinuteWindow (next_run removed)

  // Removed: dueApps (next_run removed)

  List<AppRow> dueAppsModulo(int minuteOfDay) {
    final ResultSet rs = db.select(
      'SELECT id, yaml, last_run, NULL AS next_run, interval, last_error, comments '
      'FROM apps '
      'WHERE ignore = 0 AND interval IS NOT NULL AND interval >= 1 AND ((last_run IS NULL) OR (?1 % interval) = 0) '
      'ORDER BY id ASC',
      [minuteOfDay],
    );
    return rs.map(AppRow.fromRow).toList();
  }

  // Removed: updateAfterRun (next_run removed)

  void updateAfterRunSimple({
    required String id,
    required DateTime lastRunUtc,
    required String? lastError,
  }) {
    final String lastRunIso = TimeUtils.formatMinuteUtc(lastRunUtc);
    db.execute('UPDATE apps SET last_run = ?, last_error = ? WHERE id = ?', [
      lastRunIso,
      lastError,
      id.toLowerCase(),
    ]);
  }

  // Removed: rescheduleIntoFuture (next_run removed)
}

class AppRow {
  final String id;
  final String yaml;
  final DateTime? lastRun;
  final int? interval;
  final String? lastError;
  final String? comments;

  AppRow({
    required this.id,
    required this.yaml,
    required this.lastRun,
    required this.interval,
    required this.lastError,
    required this.comments,
  });

  static AppRow fromRow(Row row) {
    final String? lastRunStr = row['last_run'] as String?;
    return AppRow(
      id: row['id'] as String,
      yaml: row['yaml'] as String,
      lastRun: lastRunStr == null ? null : TimeUtils.parseMinuteUtc(lastRunStr),
      interval: row['interval'] as int?,
      lastError: row['last_error'] as String?,
      comments: row['comments'] as String?,
    );
  }
}
