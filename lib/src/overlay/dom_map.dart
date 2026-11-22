import 'package:web/web.dart' as web;

import '../core/snapshot.dart';

/// Connects the element nodes of a snapshot to the elements of the live page.
///
/// The server describes the page as a tree; the browser parsed the same HTML
/// into a DOM. Walking both in step gives every described element its DOM
/// element without adding a single marker to the page. Where the two disagree
/// (the HTML parser inserted a `<tbody>`, a script added a node, raw HTML of
/// unknown shape) the walk steps over the difference and carries on.
class DomMap {
  DomMap._();

  /// Aligns [snapshot] with the elements that precede [dataScript], the
  /// `<script>` the server appended right after the described output.
  factory DomMap.align(AnatomySnapshot snapshot, web.Element dataScript) {
    final map = DomMap._()..expected = snapshot.elements.length;
    final expected = [for (final root in snapshot.roots) ...root.hosts];
    final parent = dataScript.parentElement;
    if (parent == null) return map;

    var actual = <web.Element>[];
    final children = parent.children;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i)!;
      if (identical(child, dataScript) || child == dataScript) break;
      actual.add(child);
    }
    // Earlier siblings that are not part of the described output would confuse
    // the walk. When the output's size is known, only look at that many.
    final count = expected.where((node) => node.isElement).length;
    if (!expected.any((node) => node.kind == NodeKind.raw) && actual.length > count) {
      actual = actual.sublist(actual.length - count);
    }
    map._alignChildren(expected, actual);
    return map;
  }

  final Map<int, web.Element> _elements = {};

  /// Element nodes the snapshot describes.
  int expected = 0;

  /// Element nodes found in the page.
  int matched = 0;

  /// The DOM element for the element node with [AnatomyNode.id] [id].
  web.Element? elementOf(int id) => _elements[id];

  /// The DOM elements that make up the output of [node]: the element itself,
  /// or for a component the outermost elements it renders.
  List<web.Element> hostsOf(AnatomyNode node) => [
    for (final host in node.hosts) ?_elements[host.id],
  ];

  void _alignChildren(List<AnatomyNode> expectedNodes, List<web.Element> actual) {
    var position = 0;
    for (var i = 0; i < expectedNodes.length; i++) {
      final node = expectedNodes[i];
      switch (node.kind) {
        case NodeKind.text || NodeKind.component:
          continue;
        case NodeKind.raw:
          // Raw HTML became an unknown number of elements. Skip to the next
          // element we do know.
          final next = _nextElement(expectedNodes, i + 1);
          if (next == null) {
            position = actual.length;
          } else {
            while (position < actual.length && !_matches(next, actual[position], strict: true)) {
              position++;
            }
          }
          continue;
        case NodeKind.element:
          var found = -1;
          // Step over a few elements the page gained since it was rendered.
          for (var k = position; k < actual.length && k <= position + 8; k++) {
            if (_matches(node, actual[k], strict: true)) {
              found = k;
              break;
            }
          }
          // Classes may have changed in the browser; the tag at the expected
          // position is still good evidence.
          if (found < 0 && position < actual.length && _matches(node, actual[position], strict: false)) {
            // Unless that element is exactly what a later sibling describes:
            // then ours is gone from the page, and taking it would shift
            // every sibling after it.
            final candidate = actual[position];
            final claimed = expectedNodes
                .skip(i + 1)
                .take(8)
                .any((later) => later.isElement && _matches(later, candidate, strict: true));
            if (!claimed) found = position;
          }
          if (found < 0) continue;
          position = found + 1;
          final element = actual[found];
          _elements[node.id] = element;
          matched++;
          final below = [for (final child in node.children) ...child.hosts];
          if (below.any((child) => child.kind != NodeKind.text)) {
            _alignChildren(below, _childElements(element, below));
          }
      }
    }
  }

  static AnatomyNode? _nextElement(List<AnatomyNode> nodes, int from) {
    for (var i = from; i < nodes.length; i++) {
      if (nodes[i].isElement) return nodes[i];
    }
    return null;
  }

  static bool _matches(AnatomyNode node, web.Element element, {required bool strict}) {
    if (element.localName.toLowerCase() != node.tag) return false;
    if (!strict) return true;
    final classes = element.classList;
    if (classes.length != node.classes.length) return false;
    for (final name in node.classes) {
      if (!classes.contains(name)) return false;
    }
    return true;
  }

  /// The element children of [element], seen the way the server wrote them:
  /// without the `<tbody>` an HTML parser puts around bare table rows.
  static List<web.Element> _childElements(web.Element element, List<AnatomyNode> expectedBelow) {
    final result = <web.Element>[];
    final children = element.children;
    final unwrapBody =
        element.localName == 'table' &&
        expectedBelow.any((node) => node.tag == 'tr') &&
        !expectedBelow.any((node) => node.tag == 'tbody');
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i)!;
      if (unwrapBody && child.localName == 'tbody') {
        final rows = child.children;
        for (var j = 0; j < rows.length; j++) {
          result.add(rows.item(j)!);
        }
      } else {
        result.add(child);
      }
    }
    return result;
  }
}

/// The rectangle of [element] in page coordinates, or null when it has no box.
Rect? pageRect(web.Element element) {
  if (!element.isConnected) return null;
  final box = element.getBoundingClientRect();
  if (box.width <= 0 && box.height <= 0) return null;
  return Rect(
    box.left.toDouble() + web.window.scrollX,
    box.top.toDouble() + web.window.scrollY,
    box.width.toDouble(),
    box.height.toDouble(),
  );
}

/// The rectangle around all of [elements], or null when none has a box.
Rect? unionRect(Iterable<web.Element> elements) {
  Rect? result;
  for (final element in elements) {
    final rect = pageRect(element);
    if (rect == null) continue;
    result = result == null ? rect : result.union(rect);
  }
  return result;
}
