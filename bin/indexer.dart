import 'dart:io';
import 'package:args/args.dart';
import 'package:indexer_new/db.dart';
import 'package:indexer_new/daemon.dart';
import 'package:indexer_new/time_utils.dart';
import 'package:indexer_new/yaml_utils.dart';
import 'package:indexer_new/process_runner.dart';
import 'package:sqlite3/sqlite3.dart';

const String version = '0.0.1';

ArgParser buildParser() {
  final ArgParser parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.');

  parser.addCommand('daemon');

  final ArgParser addCmd = ArgParser();
  parser.addCommand('add', addCmd);

  final ArgParser checkCmd = ArgParser()
    ..addOption('id', help: 'Filter by app id');
  parser.addCommand('check', checkCmd);

  // Run indexer immediately for a given id.
  parser.addCommand('index');
  // Output YAML for a given id.
  parser.addCommand('yaml');
  return parser;
}

void printUsage(ArgParser argParser) {
  stdout.writeln('Usage: indexer <flags> <command> [args]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  daemon                Run scheduler loop');
  stdout.writeln('  add <files...>        Add one or more YAML files');
  stdout.writeln(
    '  check [--id <id>]     Show next computed schedule (no next_run)',
  );
  stdout.writeln(
    '  index <id>            Run indexer immediately for the given id',
  );
  stdout.writeln('  yaml <id>             Output YAML for the given id');
  stdout.writeln('');
  stdout.writeln(argParser.usage);
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      print('indexer_new version: $version');
      return;
    }
    if (results.flag('verbose')) {
      verbose = true;
    }

    final IndexerDatabase db = IndexerDatabase.openOrCreate();

    final String? cmd = results.command?.name;
    final ArgResults? cmdResults = results.command;

    switch (cmd) {
      case 'daemon':
        final Daemon daemon = Daemon(database: db, verbose: verbose);
        await daemon.run();
        return;
      case 'add':
        final List<String> paths = cmdResults?.rest ?? <String>[];
        if (paths.isEmpty) {
          stderr.writeln('Usage: indexer add <yaml-file> [more ...]');
          return;
        }
        await _handleAdd(db: db, paths: paths, verbose: verbose);
        return;
      case 'check':
        final String? idFilter = cmdResults?['id'] as String?;
        _handleCheck(db: db, idFilter: idFilter);
        return;
      case 'index':
        final List<String> args = cmdResults?.rest ?? <String>[];
        if (args.length != 1) {
          stderr.writeln('Usage: indexer index <id>');
          return;
        }
        final String id = args.first.toLowerCase();
        final ResultSet rs = db.db.select(
          'SELECT id, yaml FROM apps WHERE id = ? LIMIT 1',
          [id],
        );
        if (rs.isEmpty) {
          stdout.writeln('Not found: $id');
          return;
        }
        final Row row = rs.first;
        final String yaml = row['yaml'] as String;
        stdout.writeln('YAML (id=$id):');
        stdout.writeln(yaml);
        stdout.writeln('--- end YAML ---');
        final DateTime nowStart = TimeUtils.nowUtc();
        final DateTime logTs = TimeUtils.truncateToMinuteUtc(nowStart);
        final ProcessResultSummary result =
            await ProcessRunner.runIndexerWithYaml(
              yaml,
              appId: id,
              logTimestampUtc: logTs,
            );
        final DateTime now = TimeUtils.truncateToMinuteUtc(TimeUtils.nowUtc());
        final String? lastError = result.success
            ? null
            : (result.stderrStr.isNotEmpty
                  ? result.stderrStr
                  : 'exit ${result.exitCode}');
        db.updateAfterRunSimple(id: id, lastRunUtc: now, lastError: lastError);
        final DateTime end = TimeUtils.nowUtc();
        final Duration took = end.difference(nowStart);
        final String tsEnd = TimeUtils.formatMinuteUtc(end);
        final int totalSeconds = took.inSeconds;
        final int minutes = totalSeconds ~/ 60;
        final int seconds = totalSeconds % 60;
        final String durStr = minutes > 0
            ? '${minutes}m ${seconds}s'
            : '${seconds}s';
        print('[$tsEnd] Done in $durStr');

        if (!result.success) {
          stderr.writeln('Indexer failed for $id');
        }
        return;
      case 'yaml':
        final List<String> args = cmdResults?.rest ?? <String>[];
        if (args.length != 1) {
          stderr.writeln('Usage: indexer yaml <id>');
          return;
        }
        final String idForYaml = args.first.toLowerCase();
        final ResultSet rsYaml = db.db.select(
          'SELECT yaml FROM apps WHERE id = ? LIMIT 1',
          [idForYaml],
        );
        if (rsYaml.isEmpty) {
          stdout.writeln('Not found: $idForYaml');
          return;
        }
        final Row rowYaml = rsYaml.first;
        final String yamlOut = rowYaml['yaml'] as String;
        stdout.writeln(yamlOut);
        return;
      default:
        stderr.writeln('Missing or unknown command.');
        printUsage(argParser);
        return;
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  }
}

Future<void> _handleAdd({
  required IndexerDatabase db,
  required List<String> paths,
  required bool verbose,
}) async {
  // Removal by signed.txt (ids line-by-line)
  final File signedFile = File('${Directory.current.path}/data/signed.txt');
  final Set<String> signedIds = <String>{};
  if (signedFile.existsSync()) {
    final List<String> lines = signedFile.readAsLinesSync();
    for (final String line in lines) {
      final String v = line.trim();
      if (v.isNotEmpty && !v.startsWith('#')) signedIds.add(v);
    }
    if (signedIds.isNotEmpty) {
      for (final String id in signedIds) {
        if (db.idExists(id)) {
          db.deleteById(id);
          if (verbose) stdout.writeln('Removed (signed): $id');
        }
      }
    }
  }

  int processed = 0;
  int skipped = 0;

  for (final String path in paths) {
    final String filename = path.split('/').isNotEmpty
        ? path.split('/').last
        : path;
    final String idFromFilename = filenameWithoutYamlExtension(filename);
    final File f = File(path);
    if (!f.existsSync()) {
      skipped++;
      stdout.writeln('skip id=$idFromFilename reason=missing file=$path');
      continue;
    }
    if (!(filename.endsWith('.yaml') || filename.endsWith('.yml'))) {
      skipped++;
      stdout.writeln('skip id=$idFromFilename reason=not-yaml file=$filename');
      continue;
    }
    if (idFromFilename.isEmpty) {
      skipped++;
      stdout.writeln('skip id= reason=empty-id file=$filename');
      continue;
    }
    final String yaml = f.readAsStringSync();
    final String? repo = extractRepository(yaml)?.trim();
    final String id = (repo != null && repo.isNotEmpty)
        ? normalizeRepositoryForId(repo)
        : idFromFilename;
    if (signedIds.contains(id)) {
      skipped++;
      stdout.writeln('skip id=$id reason=signed');
      continue;
    }

    // Default schedule policy: last_run=today 00:00Z, interval=360m
    final DateTime nowUtc = TimeUtils.nowUtc();
    final DateTime todayMidnightUtc = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
    );
    const int interval = 360;
    final DateTime defaultLast = todayMidnightUtc;

    final bool existed = db.idExists(id);

    db.upsertAppPreserveIntervalOnly(
      id: id,
      yaml: yaml,
      defaultLastRunUtc: defaultLast,
      defaultInterval: interval,
      comments: null,
    );

    if (existed) {
      stderr.writeln(
        'error id=$id reason=uniqueness-conflict (already exists)',
      );
    }

    processed++;
    if (verbose) stdout.writeln('Added: $id');
  }

  stdout.writeln('Done. Added $processed. Skipped $skipped.');
}

void _handleCheck({required IndexerDatabase db, String? idFilter}) {
  if (idFilter != null && idFilter.isNotEmpty) {
    final ResultSet rs = db.db.select(
      'SELECT id, interval FROM apps WHERE id = ? AND ignore = 0 LIMIT 1',
      [idFilter],
    );
    if (rs.isEmpty) {
      stdout.writeln('Not found: $idFilter');
      return;
    }
    final Row row = rs.first;
    final String id = row['id'] as String;
    final int? interval = row['interval'] as int?;
    final DateTime now = TimeUtils.truncateToMinuteUtc(TimeUtils.nowUtc());
    final int m = TimeUtils.minutesSinceUtcMidnight(now);
    String nextComputed = '';
    if (interval != null && interval > 0) {
      int nextMinute;
      if (m == 0) {
        nextMinute = interval;
      } else if (m % interval == 0) {
        nextMinute = m + interval;
      } else {
        nextMinute = m + (interval - (m % interval));
      }
      DateTime nextTime;
      if (nextMinute < 1440) {
        final DateTime midnight = DateTime.utc(now.year, now.month, now.day);
        nextTime = midnight.add(Duration(minutes: nextMinute));
      } else {
        final DateTime tomorrowMidnight = TimeUtils.nextUtcMidnight(now);
        final int carry = nextMinute - 1440;
        nextTime = tomorrowMidnight.add(Duration(minutes: carry));
      }
      final int minutesUntil = nextTime.difference(now).inMinutes;
      nextComputed =
          '${TimeUtils.formatMinuteUtc(nextTime)} (${minutesUntil}m)';
    }
    stdout.writeln('id           next_computed       interval');
    stdout.writeln('-----------  -------------------  --------');
    stdout.writeln(
      '${id.padRight(11)}  ${nextComputed.padRight(19)}  ${interval?.toString() ?? ''}',
    );
    return;
  }

  final ResultSet rs = db.db.select(
    'SELECT id, interval FROM apps WHERE ignore = 0 AND interval IS NOT NULL ORDER BY id ASC',
  );
  if (rs.isEmpty) {
    stdout.writeln('No apps with interval.');
    return;
  }
  final DateTime now = TimeUtils.truncateToMinuteUtc(TimeUtils.nowUtc());
  final int m = TimeUtils.minutesSinceUtcMidnight(now);
  stdout.writeln('id           next_computed       interval');
  stdout.writeln('-----------  -------------------  --------');
  for (final Row row in rs) {
    final String id = row['id'] as String;
    final int? interval = row['interval'] as int?;
    String nextComputed = '';
    if (interval != null && interval > 0) {
      int nextMinute;
      if (m == 0) {
        nextMinute = interval;
      } else if (m % interval == 0) {
        nextMinute = m + interval;
      } else {
        nextMinute = m + (interval - (m % interval));
      }
      DateTime nextTime;
      if (nextMinute < 1440) {
        final DateTime midnight = DateTime.utc(now.year, now.month, now.day);
        nextTime = midnight.add(Duration(minutes: nextMinute));
      } else {
        final DateTime tomorrowMidnight = TimeUtils.nextUtcMidnight(now);
        final int carry = nextMinute - 1440;
        nextTime = tomorrowMidnight.add(Duration(minutes: carry));
      }
      final int minutesUntil = nextTime.difference(now).inMinutes;
      nextComputed =
          '${TimeUtils.formatMinuteUtc(nextTime)} (${minutesUntil}m)';
    }
    stdout.writeln(
      '${id.padRight(11)}  ${nextComputed.padRight(19)}  ${interval?.toString() ?? ''}',
    );
  }
}
