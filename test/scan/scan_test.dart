@TestOn('vm')
library;

import 'dart:io';

import 'package:jaspr_anatomy/scan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late ScanResult result;

  setUpAll(() async {
    // The example app is a real Jaspr project with its dependencies fetched.
    result = await scanProject('example');
  });

  ScannedComponent component(String name) => result.components.singleWhere((component) => component.name == name);

  test('finds the app and its component classes', () {
    expect(result.package, 'jaspr_anatomy_example');
    expect(result.packages, ['jaspr_anatomy_example']);
    expect(result.components.map((component) => component.name), containsAll(['App', 'Card', 'NavLink', 'Counter']));
    // The tool itself is not part of the app.
    expect(result.components.map((component) => component.name), isNot(contains('Anatomy')));
  });

  test('records where a class is declared and what kind it is', () {
    final card = component('Card');
    expect(card.library, 'package:jaspr_anatomy_example/components/card.dart');
    expect(p.relative(card.file, from: result.root), p.join('lib', 'components', 'card.dart'));
    expect(card.line, greaterThan(1));
    expect(card.kind, 'stateless');
    expect(card.id, 'package:jaspr_anatomy_example/components/card.dart#Card');

    expect(component('Counter').kind, 'stateful');
    expect(component('Counter').isClient, isTrue);
    expect(component('LatestNews').kind, 'async');
    expect(card.isClient, isFalse);
  });

  test('counts every place a component is constructed', () {
    final navLink = component('NavLink');
    expect(navLink.uses, hasLength(6));
    expect(navLink.usingFiles, 1);
    expect({for (final use in navLink.uses) use.within}, {'SiteHeader', 'SiteFooter'});

    final baseButton = component('BaseButton');
    expect(baseButton.uses.single.within, 'Button');
    expect(result.singleUse.map((component) => component.name), contains('BaseButton'));
  });

  test('the report names single-use components and the most used', () {
    final report = renderScanReport(result);

    expect(report, startsWith('# Components in jaspr_anatomy_example'));
    expect(report, contains('## Never constructed (0)'));
    expect(report, contains('| BaseButton | lib/components/button.dart:'));
    expect(report, contains('| NavLink | 6 | 1 |'));
  });

  test('the saved result can be read back as use counts', () {
    final file = writeScanIndex(result);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final uses = readCodeUses(result.root)!;
    expect(uses['package:jaspr_anatomy_example/components/layout.dart#NavLink'], 6);
  });

  test('a directory without a pubspec is refused with a reason', () {
    expect(
      () => scanProject(Directory.systemTemp.path),
      throwsA(isA<ScanException>().having((error) => error.message, 'message', contains('pubspec.yaml'))),
    );
  });
}
