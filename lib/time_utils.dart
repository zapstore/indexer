import 'dart:math';

class TimeUtils {
  static DateTime nowUtc() {
    return DateTime.now().toUtc();
  }

  static DateTime truncateToMinuteUtc(DateTime dt) {
    final DateTime utc = dt.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  static String formatMinuteUtc(DateTime dt) {
    final DateTime t = truncateToMinuteUtc(dt);
    final String y = t.year.toString().padLeft(4, '0');
    final String m = t.month.toString().padLeft(2, '0');
    final String d = t.day.toString().padLeft(2, '0');
    final String h = t.hour.toString().padLeft(2, '0');
    final String min = t.minute.toString().padLeft(2, '0');
    return "$y-$m-$d"
        "T"
        "$h:$min:00Z";
  }

  static DateTime parseMinuteUtc(String iso) {
    // DateTime.parse handles Z suffix; ensure UTC
    return DateTime.parse(iso).toUtc();
  }

  static DateTime addMinutes(DateTime dt, int minutes) {
    return dt.add(Duration(minutes: minutes));
  }

  static DateTime nextUtcMidnight(DateTime fromUtc) {
    final DateTime f = fromUtc.toUtc();
    final DateTime todayMidnight = DateTime.utc(f.year, f.month, f.day);
    final DateTime next = todayMidnight.add(const Duration(days: 1));
    return next;
  }

  static int minutesSinceUtcMidnight(DateTime dt) {
    final DateTime t = truncateToMinuteUtc(dt.toUtc());
    final DateTime midnight = DateTime.utc(t.year, t.month, t.day);
    return t.difference(midnight).inMinutes;
  }

  static DateTime advanceIntoFuture({
    required DateTime originalNextRun,
    required int runEveryMinutes,
    required DateTime nowUtcRounded,
  }) {
    DateTime next = originalNextRun;
    // Ensure minute precision
    next = truncateToMinuteUtc(next);
    final int step = max(2, runEveryMinutes);
    while (!next.isAfter(nowUtcRounded)) {
      next = addMinutes(next, step);
    }
    return next;
  }
}
