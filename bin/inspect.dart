import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jaspr_anatomy/inspect.dart';
import 'package:jaspr_anatomy/scan.dart' show readCodeUses;

const String _usage = '''
Shows which components make up pages served by a running Jaspr app.

The app must wrap its page body in Anatomy(child: ...) and run in debug mode.
No browser is needed: the component tree is read from the server's response.

Usage: dart run jaspr_anatomy:inspect [options] <url> [<url> ...]
''';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('json', negatable: false, help: 'Print JSON instead of Markdown.')
    ..addFlag('snapshot', negatable: false, help: 'With --json: include the full component tree of every page.')
    ..addOption('crawl', valueHelp: 'N', help: 'Also follow same-origin links until N pages have been read.')
    ..addOption(
      'scope',
      allowed: ['project', 'packages', 'all'],
      defaultsTo: 'project',
      help: 'Which components to report.',
      allowedHelp: {
        'project': 'Components written in this repository.',
        'packages': 'Also components from hosted packages.',
        'all': 'Everything, framework internals included.',
      },
    )
    ..addFlag('tree', defaultsTo: true, help: 'Include the component tree of every page.')
    ..addFlag('elements', negatable: false, help: 'Show HTML elements in the tree.')
    ..addOption('depth', valueHelp: 'N', help: 'Deepest component level to show in the tree.')
    ..addOption('min-size', valueHelp: 'N', defaultsTo: '3', help: 'Smallest inline markup to report as repeated.')
    ..addOption('max-findings', valueHelp: 'N', defaultsTo: '20', help: 'How many repeated-markup findings to print.')
    ..addMultiOption('header', abbr: 'H', valueHelp: 'Name: value', help: 'Extra request header. Repeatable.')
    ..addOption('cookie', valueHelp: 'name=value; ...', help: 'Cookie header, for pages behind a login.')
    ..addOption('root', valueHelp: 'DIR', help: 'Show file paths relative to DIR. Defaults to the current directory.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n$_usage\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (args.flag('help') || args.rest.isEmpty) {
    stdout.writeln('$_usage\n${parser.usage}');
    exitCode = args.flag('help') ? 0 : 64;
    return;
  }

  int? intOption(String name) {
    final value = args.option(name);
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      stderr.writeln('--$name expects a whole number, got "$value".');
      exit(64);
    }
    return parsed;
  }

  final urls = <Uri>[];
  for (final value in args.rest) {
    final url = Uri.tryParse(value);
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      stderr.writeln('"$value" is not a full URL. Example: http://localhost:8080/');
      exitCode = 64;
      return;
    }
    urls.add(url);
  }

  final headers = <String, String>{};
  for (final header in args.multiOption('header')) {
    final index = header.indexOf(':');
    if (index <= 0) {
      stderr.writeln('--header expects "Name: value", got "$header".');
      exitCode = 64;
      return;
    }
    headers[header.substring(0, index).trim()] = header.substring(index + 1).trim();
  }
  if (args.option('cookie') case final cookie?) headers['cookie'] = cookie;

  final scope = switch (args.option('scope')) {
    'all' => Scope.all,
    'packages' => Scope.packages,
    _ => Scope.project,
  };
  final crawl = intOption('crawl');
  final root = args.option('root') ?? Directory.current.path;

  final inspector = Inspector(headers: headers);
  final List<InspectedPage> pages;
  try {
    pages = crawl == null
        ? [for (final url in urls) await inspector.fetch(url)]
        : await inspector.crawl(
            urls,
            limit: crawl,
            onSkip: (url, reason) => stderr.writeln('Skipped $url: $reason'),
          );
  } on InspectException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  } finally {
    inspector.close();
  }

  final snapshots = [for (final page in pages) page.snapshot];
  final analysis = Analysis(snapshots, scope: scope, minSize: intOption('min-size') ?? 3);

  if (args.flag('json')) {
    final json = analysisToJson(analysis, root: root);
    if (args.flag('snapshot')) json['snapshots'] = [for (final snapshot in snapshots) snapshot.toJson()];
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(json));
  } else {
    stdout.write(
      renderReport(
        analysis,
        options: ReportOptions(
          tree: args.flag('tree'),
          treeOptions: TreeOptions(scope: scope, elements: args.flag('elements'), maxDepth: intOption('depth')),
          maxFindings: intOption('max-findings') ?? 20,
          root: root,
          // Present after "dart run jaspr_anatomy:scan" was run in the app.
          codeUses: readCodeUses(root),
        ),
      ),
    );
  }
}
