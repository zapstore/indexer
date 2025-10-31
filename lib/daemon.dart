import 'dart:async';

import 'db.dart';
import 'process_runner.dart';
import 'time_utils.dart';
import 'ansi_utils.dart';

class Daemon {
  final IndexerDatabase database;
  final bool verbose;

  Daemon({required this.database, required this.verbose});

  Future<void> run() async {
    while (true) {
      final DateTime now = TimeUtils.truncateToMinuteUtc(TimeUtils.nowUtc());
      await _tick(now);
      // Sleep until the next minute boundary
      final DateTime nextMinute = now.add(const Duration(minutes: 1));
      final Duration sleep = nextMinute.difference(TimeUtils.nowUtc());
      await Future<void>.delayed(sleep.isNegative ? Duration.zero : sleep);
    }
  }

  Future<void> _tick(DateTime nowUtcRounded) async {
    final DateTime tickStartUtc = TimeUtils.nowUtc();
    int ranCount = 0;
    final int minuteOfDay = TimeUtils.minutesSinceUtcMidnight(nowUtcRounded);
    final List<AppRow> due = database.dueAppsModulo(minuteOfDay);
    for (final AppRow app in due) {
      // Disabled behavior: if interval is NULL, app won't run
      if (app.interval == null) {
        continue;
      }
      final int interval = app.interval!;
      if (interval < 1) {
        continue;
      }

      // Determine run state.
      final bool hasNeverRun = app.lastRun == null;

      // Map day-of-month (1..26) to letter (a..z), only if within 1..26.
      bool shouldOverwrite = false;
      if (hasNeverRun) {
        // First-ever run: overwrite regardless of starting-letter rule.
        shouldOverwrite = true;
      } else {
        final int dayOfMonth = nowUtcRounded.day;
        if (dayOfMonth >= 1 && dayOfMonth <= 26) {
          final int codeA = 'a'.codeUnitAt(0);
          final String letter = String.fromCharCode(codeA + dayOfMonth - 1);
          final String idLower = app.id.toLowerCase();
          final String idToCheck = idLower.contains('/')
              ? idLower.split('/').last
              : idLower;
          if (idToCheck.startsWith(letter)) {
            shouldOverwrite = true;
          }
        }
      }

      final ProcessResultSummary result =
          await ProcessRunner.runIndexerWithYaml(
            app.yaml,
            appId: app.id,
            logTimestampUtc: nowUtcRounded,
            overwriteApp: shouldOverwrite,
          );
      ranCount++;
      final String? lastError = result.success
          ? null
          : (() {
              final String combined = result.stderrStr.isNotEmpty
                  ? result.stderrStr
                  : result.stdoutStr;
              final String sanitized = sanitizeProcessOutput(combined);
              return sanitized.isNotEmpty
                  ? sanitized
                  : 'exit ${result.exitCode}';
            })();

      database.updateAfterRunSimple(
        id: app.id,
        lastRunUtc: nowUtcRounded,
        lastError: lastError,
      );
    }

    if (ranCount > 0) {
      final DateTime end = TimeUtils.nowUtc();
      final Duration took = end.difference(tickStartUtc);
      final String tsEnd = TimeUtils.formatMinuteUtc(end);
      final int totalSeconds = took.inSeconds;
      final int minutes = totalSeconds ~/ 60;
      final int seconds = totalSeconds % 60;
      final String durStr = minutes > 0
          ? '${minutes}m ${seconds}s'
          : '${seconds}s';
      print('[$tsEnd] Done in $durStr');
    }
  }
}
