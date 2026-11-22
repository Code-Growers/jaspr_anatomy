@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_anatomy/jaspr_anatomy.dart';
import 'package:jaspr_anatomy/snapshot.dart';
import 'package:jaspr_anatomy/src/overlay/dom_map.dart';
import 'package:jaspr_anatomy/src/overlay/live.dart';
import 'package:jaspr_test/client_test.dart';
import 'package:web/web.dart' as web;

class Panel extends StatefulComponent {
  const Panel({super.key});

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  bool open = false;

  @override
  Component build(BuildContext context) => div(classes: 'panel', [
    button(classes: 'toggle', onClick: () => setState(() => open = !open), [Component.text('toggle')]),
    if (open) const Detail(),
  ]);
}

class Detail extends StatelessComponent {
  const Detail({super.key});

  @override
  Component build(BuildContext context) => p(classes: 'detail', [Component.text('more')]);
}

AnatomyNode e(String tag, [String classes = '', List<AnatomyNode> children = const []]) =>
    AnatomyNode.element(tag: tag, classes: splitClasses(classes), children: [...children]);

AnatomyNode c(int type, List<AnatomyNode> children, {String? client}) =>
    AnatomyNode.component(type: type, client: client, children: [...children]);

/// A live tree over [snapshot] whose element nodes are [elements], in document order.
LiveTree liveOf(AnatomySnapshot snapshot, List<web.Element> elements) {
  final map = <int, web.Element>{};
  var i = 0;
  for (final node in snapshot.elements) {
    map[node.id] = elements[i++];
  }
  return LiveTree(snapshot.encode(), snapshot, map);
}

void main() {
  group('client collector', () {
    testClient('describes the live tree and follows changes', (tester) async {
      tester.pumpComponent(const Anatomy(child: Panel()));
      expect(LiveTree.available, isTrue);

      var live = LiveTree.read()!;
      expect([for (final node in live.snapshot.components) live.snapshot.typeOf(node).name], ['Panel']);
      final panel = live.snapshot.elements.firstWhere((node) => node.tag == 'div');
      expect(live.elements[panel.id], web.document.querySelector('.panel'));

      await tester.click(find.tag('button'));
      live = LiveTree.read()!;
      expect([for (final node in live.snapshot.components) live.snapshot.typeOf(node).name], ['Panel', 'Detail']);
      final detail = live.snapshot.elements.firstWhere((node) => node.tag == 'p');
      expect(live.elements[detail.id], web.document.querySelector('.detail'));
    });

    testClient('leaves the page markup alone', (tester) async {
      tester.pumpComponent(const Anatomy(child: Panel()));
      final withAnatomy = web.document.body!.innerHTML;
      tester.binding.detachRootComponent();
      web.document.body!.replaceChildren(<web.Node>[].toJS);
      tester.pumpComponent(const Panel());
      expect(withAnatomy, web.document.body!.innerHTML);
    });
  });

  group('combine', () {
    late web.HTMLElement stage;

    setUp(() {
      stage = web.document.createElement('div') as web.HTMLElement;
      web.document.body!.appendChild(stage);
    });

    tearDown(() => stage.remove());

    test('a client-mode page is described by the live tree alone', () {
      stage.innerHTML = '<div class="a"><span></span></div>'.toJS;
      final live = AnatomySnapshot(
        types: [ComponentType(name: 'Card')],
        roots: [
          c(0, [
            e('div', 'a', [e('span')]),
          ]),
        ],
      );
      final (snapshot, dom) = combine(
        null,
        null,
        liveOf(live, [stage.querySelector('.a')!, stage.querySelector('span')!]),
      );
      expect(snapshot.components.single.type, 0);
      expect(dom.hostsOf(snapshot.components.single), [stage.querySelector('.a')]);
    });

    test('an island is replaced by what it renders now, with the server names', () {
      stage.innerHTML = '<div class="page"><div class="counter"><button></button><p class="new"></p></div></div>'.toJS;
      final page = stage.querySelector('.page')!;
      final counter = stage.querySelector('.counter')!;
      final buttonEl = stage.querySelector('button')!;
      final newEl = stage.querySelector('.new')!;

      // What the server rendered: the island had only its button.
      final server = AnatomySnapshot(
        types: [
          ComponentType(name: 'Page', library: 'package:app/page.dart', origin: Origin.project),
          ComponentType(name: 'Counter', library: 'package:app/counter.dart', origin: Origin.project),
          ComponentType(name: 'Button', library: 'package:app/button.dart', origin: Origin.project),
        ],
        roots: [
          c(0, [
            e('div', 'page', [
              c(1, client: 'counter', [
                e('div', 'counter', [
                  c(2, [e('button')]),
                ]),
              ]),
            ]),
          ]),
        ],
      );
      final serverDom = DomMap.known(server, {
        for (final node in server.elements)
          node.id: switch (node.tag) {
            'button' => buttonEl,
            _ => node.classes.first == 'page' ? page : counter,
          },
      });

      // A minified client: names are lost, and a helper shows up as a component.
      final live = AnatomySnapshot(
        types: [
          ComponentType(name: 'minified:Ab'),
          ComponentType(name: 'minified:Cd'),
          ComponentType(name: 'minified:Ef'),
          ComponentType(name: 'minified:Gh'),
        ],
        roots: [
          c(0, client: 'minified:Ab', [
            e('div', 'counter', [
              c(1, [e('button')]),
              c(3, [
                c(2, [e('p', 'new')]),
              ]),
            ]),
          ]),
        ],
      );

      final (snapshot, dom) = combine(server, serverDom, liveOf(live, [counter, buttonEl, newEl]));
      final names = [for (final node in snapshot.components) snapshot.typeOf(node).name];
      expect(names, ['Page', 'Counter', 'Button', 'minified:Gh']);
      final island = snapshot.components.firstWhere((node) => snapshot.typeOf(node).name == 'Counter');
      expect(island.client, 'counter');
      expect(snapshot.typeOf(island).library, 'package:app/counter.dart');
      final added = snapshot.components.last;
      expect(dom.hostsOf(added), [newEl]);
      expect(dom.hostsOf(snapshot.components.first), [page]);
    });
  });
}
