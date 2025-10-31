import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'time_utils.dart';

class ProcessResultSummary {
  final int exitCode;
  final String stdoutStr;
  final String stderrStr;

  ProcessResultSummary({
    required this.exitCode,
    required this.stdoutStr,
    required this.stderrStr,
  });

  bool get success => exitCode == 0;
}

class ProcessRunner {
  static Future<ProcessResultSummary> runIndexerWithYaml(
    String yaml, {
    required String appId,
    required DateTime logTimestampUtc,
    bool overwriteApp = false,
  }) async {
    final List<String> args = <String>['publish', '--indexer-mode'];
    if (overwriteApp) {
      args.add('--overwrite-release');
      args.add('--overwrite-app');
    }
    final Map<String, String> env = Map<String, String>.from(
      Platform.environment,
    );
    // Disable color/ANSI in child process if supported by CLI
    env['NO_COLOR'] = '1';
    env['CLICOLOR'] = '0';
    env['CLICOLOR_FORCE'] = '0';
    // Some CLIs honor FORCE_COLOR=0
    env['FORCE_COLOR'] = '0';
    // TERM=dumb signals minimal capabilities
    env['TERM'] = 'dumb';
    final Process process = await Process.start(
      'zapstore',
      args,
      environment: env,
      mode: ProcessStartMode.normal,
    );
    process.stdin.add(utf8.encode(yaml));
    await process.stdin.close();
    final StringBuffer outBuffer = StringBuffer();
    final StringBuffer errBuffer = StringBuffer();

    bool headerPrinted = false;
    void _maybePrintHeader() {
      if (!headerPrinted) {
        final String ts = TimeUtils.formatMinuteUtc(logTimestampUtc);
        stdout.writeln('[$ts] Output for $appId');
        headerPrinted = true;
      }
    }

    final Completer<void> stdoutDone = Completer<void>();
    final Completer<void> stderrDone = Completer<void>();

    process.stdout.transform(utf8.decoder).listen((String data) {
      if (data.isNotEmpty) {
        _maybePrintHeader();
      }
      outBuffer.write(data);
      stdout.write(data);
    }, onDone: () => stdoutDone.complete());

    process.stderr.transform(utf8.decoder).listen((String data) {
      if (data.isNotEmpty) {
        _maybePrintHeader();
      }
      errBuffer.write(data);
      stderr.write(data);
    }, onDone: () => stderrDone.complete());

    await Future.wait(<Future<void>>[stdoutDone.future, stderrDone.future]);
    final int code = await process.exitCode;
    return ProcessResultSummary(
      exitCode: code,
      stdoutStr: outBuffer.toString(),
      stderrStr: errBuffer.toString(),
    );
  }
}
