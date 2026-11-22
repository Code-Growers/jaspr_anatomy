@TestOn('vm')
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_anatomy/inspect.dart';
import 'package:jaspr_anatomy/jaspr_anatomy.dart';
import 'package:jaspr_test/server_test.dart';

import '../support/fixtures.dart';

/// Two components with different names that render the same structure.
class Tile extends StatelessComponent {
  const Tile({super.key});

  @override
  Component build(BuildContext context) => div(classes: 'tile', [
    span([Component.text('a')]),
    span([Component.text('b')]),
  ]);
}

class Panel extends StatelessComponent {
  const Panel({super.key});

  @override
  Component build(BuildContext context) => div(classes: 'tile', [
    span([Component.text('c')]),
    span([Component.text('d')]),
  ]);
}

/// Three rows written inline, with different inner content.
class Listing extends StatelessComponent {
  const Listing({super.key});

  @override
  Component build(BuildContext context) {
    Component row(String label, {bool extra = false}) => li(classes: 'row', [
      span(classes: 'row-label', [Component.text(label)]),
      span(classes: 'row-value', [
        Component.text('1'),
        if (extra) em([Component.text('!')]),
      ]),
    ]);
    return ul([row('a'), row('b'), row('c', extra: true)]);
  }
}

Future<AnatomySnapshot> snapshotOf(ServerTester tester, Component component, [String url = '/?anatomy=data']) async {
  tester.pumpComponent(Anatomy(enabled: true, child: component));
  final response = await tester.request(url);
  return extractSnapshot(response.body)!;
}

void main() {
  setUp(() {
    Jaspr.initializeApp(
      options: ServerOptions(clients: {Counter: ClientTarget<Counter>('counter')}),
    );
  });

  group('usage', () {
    testServer('counts instances, containers and own elements', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const FixturePage())]);

      TypeUsage usage(String name) => analysis.types.firstWhere((usage) => usage.type.name == name);

      expect(usage('NavLink').instances, 3);
      expect(usage('NavLink').containers, {'SiteHeader': 3});
      expect(usage('Card').instances, 3);
      expect(usage('Card').containers, {'FixturePage': 3});
      expect(usage('BaseButton').instances, 3);
      expect(usage('BaseButton').containers, {'Button': 2, 'Counter': 1});
      expect(usage('FixturePage').containers, {'': 1});

      // div.card, h3 and div.card-body per card.
      expect(usage('Card').ownElements, 9);
      // A wrapper that only delegates writes no elements itself.
      expect(usage('Button').ownElements, 0);

      expect(analysis.types.first.instances, 3);
      expect(analysis.pages.single.components, 16);
    });

    testServer('framework components are out of scope unless asked for', (tester) async {
      final snapshot = await snapshotOf(tester, Builder(builder: (context) => const FixturePage()));

      expect(Analysis([snapshot]).types.map((usage) => usage.type.name), isNot(contains('Builder')));
      expect(Analysis([snapshot], scope: Scope.all).types.map((usage) => usage.type.name), contains('Builder'));
    });

    testServer('the reuse share counts elements written by components used more than once', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const FixturePage())]);
      final page = analysis.pages.single;

      // NavLink ×3 (3), Card ×3 (9), BaseButton ×3 (3) out of all elements.
      expect(page.reusedElements, 15);
      expect(page.reuseShare, closeTo(15 / page.elements, 0.0001));
      expect(analysis.oneOffs.first.type.name, 'FixturePage');
    });
  });

  group('repeated markup', () {
    testServer('inline markup that matches a component is reported, healthy reuse is not', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const FixturePage())]);

      final finding = analysis.findings.single;
      expect(finding.kind, FindingKind.duplicatesComponent);
      expect(finding.components, ['Card']);
      expect(finding.shape, 'div.card > (h3.card-title + div.card-body)');
      expect(finding.occurrences, hasLength(4));
      expect(finding.inlineOwners, {'FixturePage': 1});
      expect(finding.identical, isFalse);
      expect(describeFinding(finding), contains('Inline markup duplicates `Card`'));
    });

    testServer('two components that render the same structure are twins', (tester) async {
      final analysis = Analysis([
        await snapshotOf(tester, div([const Tile(), const Panel(), const Tile()])),
      ]);

      final finding = analysis.findings.single;
      expect(finding.kind, FindingKind.twinComponents);
      expect(finding.components, ['Panel', 'Tile']);
      expect(finding.identical, isTrue);
    });

    testServer('inline repetition with differing contents is a candidate', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const Listing())]);

      final finding = analysis.findings.single;
      expect(finding.kind, FindingKind.repeatedInline);
      expect(finding.shape, 'li.row > (span.row-label + span.row-value)');
      expect(finding.occurrences, hasLength(3));
      expect(finding.inlineOwners, {'Listing': 3});
      expect((finding.minElements, finding.maxElements), (3, 4));
      expect(finding.identical, isFalse);
    });

    testServer('small unclassed repetition is ignored', (tester) async {
      final analysis = Analysis([
        await snapshotOf(
          tester,
          ul([
            li([Component.text('a')]),
            li([Component.text('b')]),
            li([Component.text('c')]),
          ]),
        ),
      ]);

      expect(analysis.findings, isEmpty);
    });

    testServer('a layout shared by every page does not hide what is inside it', (tester) async {
      Component shell(Component content) => div(classes: 'shell', [
        header(classes: 'top', [Component.text('Site')]),
        main_([content]),
      ]);
      final first = await snapshotOf(tester, shell(const Tile()), '/a?anatomy=data');
      final second = await snapshotOf(tester, shell(const Panel()), '/b?anatomy=data');
      final analysis = Analysis([first, second]);

      final finding = analysis.findings.single;
      expect(finding.kind, FindingKind.twinComponents);
      expect(finding.components, ['Panel', 'Tile']);
    });

    testServer('markup that appears once per page is not repetition', (tester) async {
      // The same wrapper around every page, written outside any component.
      Component page(String title) => div(classes: 'frame', [
        h1(classes: 'frame-title', [Component.text(title)]),
        div(classes: 'frame-body', [const TextOnly()]),
      ]);
      final analysis = Analysis([
        await snapshotOf(tester, page('One'), '/a?anatomy=data'),
        await snapshotOf(tester, page('Two'), '/b?anatomy=data'),
        await snapshotOf(tester, page('Three'), '/c?anatomy=data'),
      ]);

      expect(analysis.findings, isEmpty);
    });

    testServer('markup that appears once in every instance of a component is not repetition', (tester) async {
      // Card's own h3 and body exist once per card.
      final analysis = Analysis([
        await snapshotOf(
          tester,
          div([
            const Card(title: 'a', child: TextOnly()),
            const Card(title: 'b', child: TextOnly()),
          ]),
        ),
      ]);

      expect(analysis.findings, isEmpty);
    });

    testServer('findings merge across pages', (tester) async {
      final first = await snapshotOf(tester, const Listing(), '/a?anatomy=data');
      final second = await snapshotOf(tester, const Listing(), '/b?anatomy=data');
      final analysis = Analysis([first, second]);

      expect(analysis.pages, hasLength(2));
      final finding = analysis.findings.single;
      expect(finding.occurrences, hasLength(6));
      expect(finding.pages, hasLength(2));
      expect(analysis.types.single.pages, 2);
      // Listing now has two instances, so its markup counts as reused.
      expect(analysis.reuseShare, 1);
    });
  });

  group('report', () {
    testServer('the tree merges identical neighbours and names sources once', (tester) async {
      final tree = renderTree(await snapshotOf(tester, const FixturePage()), root: '/nowhere');

      expect(tree, contains('FixturePage  — '));
      expect(tree, contains('    NavLink ×3'));
      expect(tree, contains('  Card ×2'));
      expect(tree, contains('    Counter (client)'));
      expect('NavLink'.allMatches(tree), hasLength(1));
      expect('fixtures.dart'.allMatches(tree).length, lessThanOrEqualTo(9));
    });

    testServer('the tree can show elements and stop at a depth', (tester) async {
      final snapshot = await snapshotOf(tester, const FixturePage());

      expect(renderTree(snapshot, options: const TreeOptions(elements: true)), contains('<div.page>'));
      final shallow = renderTree(snapshot, options: const TreeOptions(maxDepth: 1, sources: false));
      expect(shallow.trim().split('\n').map((text) => text.trim()).toSet(), {
        'FixturePage',
        'SiteHeader',
        'Card ×3',
        'TextOnly',
        'Pair',
      });
    });

    testServer('the Markdown report has every section', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const FixturePage())]);
      final report = renderReport(analysis);

      expect(report, startsWith('# Anatomy of /?anatomy=data'));
      expect(report, contains('## Components'));
      expect(report, contains('| NavLink | 3 |'));
      expect(report, contains('## Where inline markup accumulates'));
      expect(report, contains('## Repeated markup'));
      expect(report, contains('1. Inline markup duplicates `Card`'));
      expect(report, contains('## Tree'));
    });

    testServer('the JSON form is encodable and complete', (tester) async {
      final analysis = Analysis([await snapshotOf(tester, const FixturePage())]);
      final json = analysisToJson(analysis);

      expect((json['components']! as List).length, analysis.types.length);
      expect(((json['findings']! as List).single as Map)['kind'], 'duplicatesComponent');
    });
  });

  group('snapshot', () {
    testServer('survives a JSON round trip', (tester) async {
      final snapshot = await snapshotOf(tester, const FixturePage());
      final copy = AnatomySnapshot.decode(snapshot.encode());

      expect(copy.encode(), snapshot.encode());
      expect(copy.nodes.length, snapshot.nodes.length);
      expect(copy.nodes[5].parent, isNotNull);
      expect(copy.nodes.indexed.every((entry) => entry.$2.id == entry.$1), isTrue);
    });
  });
}
