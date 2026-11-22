import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jaspr_anatomy/scan.dart';

const String _usage = '''
Lists the component classes of a Jaspr app and where each is constructed,
by reading source. The app does not need to run.

Covers the app and the local packages it depends on (path dependencies and
workspace members), so shared component libraries are included.

Usage: dart run jaspr_anatomy:scan [options] [<app directory>]
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('json', negatable: false, help: 'Print JSON instead of Markdown.')
    ..addOption('limit', valueHelp: 'N', defaultsTo: '25', help: 'Longest list to print in the Markdown report.')
    ..addFlag(
      'write',
      defaultsTo: true,
      help: 'Save the result to $scanIndexPath in the app, for other tools.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n$_usage\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (args.flag('help') || args.rest.length > 1) {
    stdout.writeln('$_usage\n${parser.usage}');
    exitCode = args.flag('help') ? 0 : 64;
    return;
  }
  final limit = int.tryParse(args.option('limit')!);
  if (limit == null || limit < 1) {
    stderr.writeln('--limit expects a whole number above zero.');
    exitCode = 64;
    return;
  }

  final ScanResult result;
  try {
    result = await scanProject(args.rest.isEmpty ? Directory.current.path : args.rest.single);
  } on ScanException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  if (args.flag('write')) writeScanIndex(result);
  if (args.flag('json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  } else {
    stdout.write(renderScanReport(result, limit: limit));
  }
}
