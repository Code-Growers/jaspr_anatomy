@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_anatomy/jaspr_anatomy.dart';
import 'package:jaspr_anatomy/snapshot.dart';
import 'package:jaspr_test/server_test.dart';

import '../support/fixtures.dart';

final RegExp _dataScript = RegExp(
  '<script type="application/json" id="$anatomyDataId"[^>]*>(.*?)</script>',
  dotAll: true,
);
final RegExp _anyAnatomyScript = RegExp(r'\s*<script[^>]*id="__jaspr_anatomy[^"]*"[^>]*>.*?</script>', dotAll: true);

AnatomySnapshot snapshotIn(String html) {
  final match = _dataScript.firstMatch(html);
  expect(match, isNotNull, reason: 'no anatomy data script in:\n$html');
  return AnatomySnapshot.decode(match!.group(1)!);
}

String withoutAnatomy(String html) => html.replaceAll(_anyAnatomyScript, '');

String collapse(String html) => html.replaceAll(RegExp(r'\s+'), ' ').replaceAll('> <', '><').trim();

/// Component names in depth-first order.
List<String> componentNames(AnatomySnapshot snapshot) => [
  for (final node in snapshot.components) snapshot.typeOf(node).name,
];

void main() {
  setUp(() {
    Jaspr.initializeApp(
      options: ServerOptions(
        clientId: 'main.client.dart.js',
        clients: {Counter: ClientTarget<Counter>('counter')},
      ),
    );
  });

  group('when the request does not ask', () {
    testServer('a disabled wrapper leaves the page byte-identical', (tester) async {
      tester.pumpComponent(const FixturePage());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: false, child: FixturePage()));
      final wrapped = await tester.request('/?anatomy');

      expect(wrapped.body, plain.body);
    });

    testServer('with the hotkey off the page is byte-identical', (tester) async {
      tester.pumpComponent(const FixturePage());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: true, hotkey: false, child: FixturePage()));
      final wrapped = await tester.request('/');

      expect(wrapped.body, plain.body);
    });

    testServer('only the hotkey listener is added', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final response = await tester.request('/');

      expect(response.body, contains('id="$anatomyHotkeyId"'));
      expect(response.body, isNot(contains(anatomyDataId)));
      expect(response.body, isNot(contains(anatomyOverlayId)));
    });

    testServer('?anatomy=0 wins over the cookie', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final response = await tester.request('/?anatomy=0');

      expect(response.body, isNot(contains(anatomyDataId)));
    });
  });

  group('when the request asks', () {
    testServer('the app markup is unchanged apart from the appended scripts', (tester) async {
      tester.pumpComponent(const FixturePage());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final wrapped = await tester.request('/?anatomy=data');

      expect(wrapped.statusCode, 200);
      // Exactly the same markup, whitespace included.
      expect(withoutAnatomy(wrapped.body), plain.body);
    });

    testServer('a page that fits on one line only gains whitespace around the app root', (tester) async {
      tester.pumpComponent(const Hostile());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: true, child: Hostile()));
      final wrapped = await tester.request('/?anatomy=data');

      expect(collapse(withoutAnatomy(wrapped.body)), collapse(plain.body));
    });

    testServer('the snapshot lists components in document order without HTML helpers', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final snapshot = snapshotIn((await tester.request('/?anatomy=data')).body);

      expect(componentNames(snapshot), [
        'FixturePage',
        'SiteHeader',
        'NavLink',
        'NavLink',
        'NavLink',
        'Card',
        'Button',
        'BaseButton',
        'Card',
        'Button',
        'BaseButton',
        'Card',
        'Counter',
        'BaseButton',
        'TextOnly',
        'Pair',
      ]);
      expect(snapshot.url, '/?anatomy=data');
    });

    testServer('elements carry tag and classes, components their hosts', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final snapshot = snapshotIn((await tester.request('/?anatomy=data')).body);

      final page = snapshot.roots.single;
      expect(snapshot.typeOf(page).name, 'FixturePage');
      final root = page.children.single;
      expect(root.tag, 'div');
      expect(root.classes, ['page']);

      final card = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'Card');
      final host = card.hosts.single;
      expect(host.tag, 'div');
      expect(host.classes, ['card']);
      expect(host.children.map((child) => child.tag), ['h3', 'div']);

      // A wrapper and the component it wraps share one host element.
      final button = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'Button');
      expect(button.hosts.single.classes, ['btn', 'btn-primary']);
      expect(button.children.single.isComponent, isTrue);

      final pair = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'Pair');
      expect(pair.hosts.map((host) => host.classes.single), ['first', 'second']);

      final textOnly = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'TextOnly');
      expect(textOnly.hosts.single.kind, NodeKind.text);
      expect(textOnly.hosts.single.text, 'Just text');
    });

    testServer('component types know their library, file, line and origin', (tester) async {
      tester.pumpComponent(Anatomy(enabled: true, child: Builder(builder: (context) => const FixturePage())));
      final snapshot = snapshotIn((await tester.request('/?anatomy=data')).body);

      final card = snapshot.types.firstWhere((type) => type.name == 'Card');
      expect(card.library, endsWith('test/support/fixtures.dart'));
      expect(card.file, endsWith('test/support/fixtures.dart'));
      expect(card.line, greaterThan(1));
      expect(card.origin, Origin.project);

      final builder = snapshot.types.firstWhere((type) => type.name == 'Builder');
      expect(builder.package, 'jaspr');
      expect(builder.origin, Origin.framework);
    });

    testServer('a client component is marked and its markers are untouched', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: FixturePage()));
      final response = await tester.request('/?anatomy=data');
      final snapshot = snapshotIn(response.body);

      final counter = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'Counter');
      expect(counter.client, 'counter');
      expect(snapshot.components.where((node) => node.client != null), hasLength(1));
      // The first render inside the client component is described too.
      expect(counter.descendants.where((node) => node.isComponent), hasLength(1));

      expect(response.body, contains('<!--@counter-->'));
      expect(response.body, contains('<!--/@counter-->'));
    });

    testServer('scripts land after the markers when the child is a client component', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: Counter()));
      final body = (await tester.request('/?anatomy=data')).body;

      final end = body.indexOf('<!--/@counter-->');
      final script = body.indexOf(anatomyDataId);
      expect(end, greaterThan(0));
      expect(script, greaterThan(end));
    });

    testServer('the header asks for data only', (tester) async {
      final result = await renderComponent(
        const Anatomy(enabled: true, child: FixturePage()),
        request: Request('GET', Uri.parse('http://test.server/'), headers: {anatomyHeader: 'data'}),
      );
      final body = utf8.decode(result.body);

      expect(snapshotIn(body).roots, isNotEmpty);
      expect(body, isNot(contains(anatomyOverlayId)));
      expect(body, isNot(contains(anatomyHotkeyId)));
    });

    testServer('the data script tells the overlay the project root and the editor link', (tester) async {
      tester.pumpComponent(
        const Anatomy(enabled: true, editorUrl: 'idea://open?file={file}&line={line}', child: FixturePage()),
      );
      final document = (await tester.request('/?anatomy=data')).document!;
      final script = document.getElementById(anatomyDataId)!;

      expect(script.attributes['data-root'], Directory.current.path);
      expect(script.attributes['data-editor'], 'idea://open?file={file}&line={line}');
    });

    testServer('text that looks like a closing script tag cannot break out', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: Hostile()));
      final response = await tester.request('/?anatomy=data');
      final snapshot = snapshotIn(response.body);

      expect(snapshot.nodes.last.text, '</script><script>alert(1)</script>');
      expect(response.document!.querySelectorAll('script[id="$anatomyDataId"]'), hasLength(1));
      expect(_dataScript.firstMatch(response.body)!.group(1), isNot(contains('<')));
    });
  });

  group('output shapes', () {
    testServer('async components are described in document order', (tester) async {
      tester.pumpComponent(
        Anatomy(
          enabled: true,
          child: div([const SlowSection(), const Button(label: 'Early')]),
        ),
      );
      final snapshot = snapshotIn((await tester.request('/?anatomy=data')).body);

      expect(componentNames(snapshot), ['SlowSection', 'Button', 'BaseButton', 'Button', 'BaseButton']);
      final slow = snapshot.components.first;
      expect(slow.hosts.single.classes, ['slow']);
    });

    testServer('a component that throws does not change the outcome', (tester) async {
      Component page() => div([const Throwing(), const AsyncThrowing(), const Button(label: 'Still here')]);

      tester.pumpComponent(page());
      final plain = await tester.request('/');
      tester.pumpComponent(Anatomy(enabled: true, child: page()));
      final wrapped = await tester.request('/?anatomy=data');

      expect(wrapped.statusCode, plain.statusCode);
      expect(collapse(withoutAnatomy(wrapped.body)), collapse(plain.body));
      expect(componentNames(snapshotIn(wrapped.body)), containsAll(['Throwing', 'AsyncThrowing', 'Button']));
    });

    testServer('a wrapper whose own child throws is skipped quietly', (tester) async {
      tester.pumpComponent(const Throwing());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: true, child: Throwing()));
      final wrapped = await tester.request('/?anatomy=data');

      expect(wrapped.statusCode, plain.statusCode);
    });

    testServer('raw text parents and raw HTML are left alone', (tester) async {
      tester.pumpComponent(const RawTextParents());
      final plain = await tester.request('/');
      tester.pumpComponent(const Anatomy(enabled: true, child: RawTextParents()));
      final wrapped = await tester.request('/?anatomy=data');

      expect(collapse(withoutAnatomy(wrapped.body)), collapse(plain.body));
      final snapshot = snapshotIn(wrapped.body);
      expect(snapshot.nodes.where((node) => node.kind == NodeKind.raw), isNotEmpty);
      expect(componentNames(snapshot), containsAll(['RawTextParents', 'TextOnly', 'Button']));
    });

    testServer('content moved into the head is not described as body content', (tester) async {
      tester.pumpComponent(const Anatomy(enabled: true, child: WithHead()));
      final response = await tester.request('/?anatomy=data');
      final snapshot = snapshotIn(response.body);

      expect(response.document!.head!.querySelector('meta[name="fixture"]'), isNotNull);
      expect(snapshot.elements.map((node) => node.tag), isNot(contains('meta')));
      final host = snapshot.roots.single.hosts.single;
      expect(host.classes, ['with-head']);
      expect(host.children.map((child) => child.kind), [NodeKind.component]);
    });
  });

  group('other render paths', () {
    testServer('the body-only hot reload response carries the data', (tester) async {
      final result = await renderComponent(
        const Anatomy(enabled: true, child: FixturePage()),
        request: Request(
          'GET',
          Uri.parse('http://test.server/?anatomy=data'),
          headers: {'X-Jaspr-Reload': 'true'},
        ),
      );
      final body = utf8.decode(result.body);

      expect(body, isNot(contains('<head>')));
      expect(snapshotIn(body).roots, isNotEmpty);
    });

    testServer('standalone rendering carries the data', (tester) async {
      final result = await renderComponent(
        const Anatomy(enabled: true, child: FixturePage()),
        request: Request('GET', Uri.parse('http://test.server/?anatomy=data')),
        standalone: true,
      );
      final body = utf8.decode(result.body);

      expect(body, isNot(contains('<html')));
      expect(snapshotIn(body).roots, isNotEmpty);
    });
  });
}
