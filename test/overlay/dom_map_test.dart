@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:jaspr_anatomy/snapshot.dart';
import 'package:jaspr_anatomy/src/overlay/dom_map.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

AnatomyNode e(String tag, [String classes = '', List<AnatomyNode> children = const []]) =>
    AnatomyNode.element(tag: tag, classes: splitClasses(classes), children: [...children]);

AnatomyNode c(List<AnatomyNode> children) => AnatomyNode.component(type: 0, children: [...children]);

AnatomySnapshot snapshotOf(List<AnatomyNode> roots) => AnatomySnapshot(
  types: [ComponentType(name: 'Thing')],
  roots: roots,
);

void main() {
  late web.HTMLElement stage;

  /// Puts [html] on the page, followed by the data script the server would add.
  web.Element render(String html) {
    stage.innerHTML = '$html<script type="application/json" id="data"></script>'.toJS;
    return stage.querySelector('#data')!;
  }

  setUp(() {
    stage = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(stage);
  });

  tearDown(() => stage.remove());

  test('every described element finds its page element', () {
    final script = render(
      '<div class="page"><header><a class="link">x</a><a class="link">y</a></header><main>m</main></div>',
    );
    final snapshot = snapshotOf([
      c([
        e('div', 'page', [
          c([
            e('header', '', [
              c([e('a', 'link')]),
              c([e('a', 'link')]),
            ]),
          ]),
          e('main'),
        ]),
      ]),
    ]);

    final map = DomMap.align(snapshot, script);

    expect(map.expected, 5);
    expect(map.matched, 5);
    final links = snapshot.elements.where((node) => node.tag == 'a').toList();
    expect(map.elementOf(links[0].id)!.textContent, 'x');
    expect(map.elementOf(links[1].id)!.textContent, 'y');
  });

  test('a component is located by the outermost elements it renders', () {
    final script = render('<section><p class="a">1</p><p class="b">2</p></section>');
    final pair = c([e('p', 'a'), e('p', 'b')]);
    final wrapper = c([pair]);
    final snapshot = snapshotOf([
      e('section', '', [wrapper]),
    ]);

    final map = DomMap.align(snapshot, script);

    expect(map.hostsOf(pair).map((element) => element.className), ['a', 'b']);
    // A wrapper renders exactly what it wraps.
    expect(map.hostsOf(wrapper), hasLength(2));
    expect(unionRect(map.hostsOf(pair)), isNotNull);
  });

  test('rows are found inside the tbody the browser adds', () {
    final script = render('<table><tr><td>a</td></tr><tr><td>b</td></tr></table>');
    expect(stage.querySelector('tbody'), isNotNull, reason: 'the parser inserts a tbody');
    final snapshot = snapshotOf([
      e('table', '', [
        e('tr', '', [e('td')]),
        e('tr', '', [e('td')]),
      ]),
    ]);

    final map = DomMap.align(snapshot, script);

    expect(map.matched, map.expected);
    expect(map.expected, 5);
  });

  test('raw HTML of unknown shape is stepped over', () {
    final script = render('<div><svg><path></path></svg><i>raw</i><span class="after">k</span></div>');
    final snapshot = snapshotOf([
      e('div', '', [AnatomyNode.raw(), e('span', 'after')]),
    ]);

    final map = DomMap.align(snapshot, script);

    final after = snapshot.elements.last;
    expect(map.elementOf(after.id)!.textContent, 'k');
    expect(map.matched, 2);
  });

  test('an element the page gained does not shift the rest', () {
    final script = render('<ul><li class="one">1</li><li class="injected">!</li><li class="two">2</li></ul>');
    final snapshot = snapshotOf([
      e('ul', '', [e('li', 'one'), e('li', 'two')]),
    ]);

    final map = DomMap.align(snapshot, script);

    final two = snapshot.elements.last;
    expect(map.elementOf(two.id)!.textContent, '2');
    expect(map.matched, 3);
  });

  test('an element the page lost is reported missing and the rest still match', () {
    final script = render('<ul><li class="one">1</li><li class="three">3</li></ul>');
    final snapshot = snapshotOf([
      e('ul', '', [
        e('li', 'one'),
        e('li', 'two', [e('b')]),
        e('li', 'three'),
      ]),
    ]);

    final map = DomMap.align(snapshot, script);

    expect(map.expected, 5);
    expect(map.matched, 3);
    final lost = snapshot.elements.firstWhere((node) => node.classes.contains('two'));
    expect(map.elementOf(lost.id), isNull);
    expect(map.elementOf(snapshot.elements.last.id)!.textContent, '3');
  });

  test('a class changed in the browser still matches by position', () {
    final script = render('<button class="toggle dark">t</button>');
    final snapshot = snapshotOf([e('button', 'toggle')]);

    expect(DomMap.align(snapshot, script).matched, 1);
  });

  test('earlier siblings that are not part of the description are ignored', () {
    final script = render('<div class="other">no</div><div class="app">yes</div>');
    final snapshot = snapshotOf([
      c([e('div', 'app')]),
    ]);

    final map = DomMap.align(snapshot, script);

    expect(map.elementOf(snapshot.elements.single.id)!.textContent, 'yes');
  });

  test('an element without an area has no rectangle', () {
    final script = render('<div class="shown">a</div><div class="gone" style="display:none">b</div>');
    final snapshot = snapshotOf([e('div', 'shown'), e('div', 'gone')]);

    final map = DomMap.align(snapshot, script);

    expect(pageRect(map.elementOf(snapshot.elements.first.id)!), isNotNull);
    expect(pageRect(map.elementOf(snapshot.elements.last.id)!), isNull);
  });
}
