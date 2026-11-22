import 'package:web/web.dart' as web;

import '../core/snapshot.dart';
import 'dom.dart';
import 'dom_map.dart';
import 'state.dart';

/// Outlines and labels drawn over the real page.
///
/// The layer sits at the top-left of the document and does not take pointer
/// events, so the page underneath stays usable.
class FlatView {
  FlatView(this.state, web.Node root) : layer = el('div', cls: 'flat') {
    root.appendChild(layer);
  }

  final OverlayState state;
  final web.HTMLElement layer;

  final Map<Box, web.HTMLElement> _nodes = Map.identity();
  final List<web.HTMLElement> _marks = [];

  /// Recreates one outline per box. Call when the boxes or the depth limit change.
  void rebuild() {
    clear(layer);
    _nodes.clear();
    _marks.clear();
    for (final box in state.boxes) {
      if (!state.withinDepth(box)) continue;
      final node = el<web.HTMLElement>(
        'div',
        cls: 'box',
        children: [el('span', cls: 'tag', text: state.labelOf(box))],
      );
      node.style.setProperty('--h', '${state.hueOf(box)}');
      layer.appendChild(node);
      _nodes[box] = node;
    }
    layout();
    highlight();
  }

  /// Moves the outlines to where their boxes are now.
  void layout() {
    // Label areas already taken, so that labels of boxes that start at the
    // same corner end up side by side instead of on top of each other.
    final taken = <Rect>[];
    _nodes.forEach((box, node) {
      final rect = box.rect;
      if (rect == null || rect.isEmpty) {
        node.style.display = 'none';
        return;
      }
      node.style
        ..display = ''
        ..left = px(rect.x)
        ..top = px(rect.y)
        ..width = px(rect.width)
        ..height = px(rect.height);
      final small = rect.width < 28 || rect.height < 10;
      final inside = rect.y < _labelHeight + 1;
      node.classList
        ..toggle('small', small)
        ..toggle('inside', inside);
      if (small) return;

      final width = state.labelOf(box).length * 5.6 + 8;
      final top = inside ? rect.y : rect.y - _labelHeight;
      var left = rect.x;
      for (var attempt = 0; attempt < 6; attempt++) {
        final overlap = taken.where(
          (other) => left < other.right && left + width > other.x && top < other.bottom && top + _labelHeight > other.y,
        );
        if (overlap.isEmpty) break;
        left = overlap.map((other) => other.right).reduce((a, b) => a > b ? a : b) + 2;
      }
      taken.add(Rect(left, top, width, _labelHeight));
      node.style.setProperty('--dx', px(left - rect.x));
    });
    _layoutMarks();
  }

  static const double _labelHeight = 14;

  /// Applies hover, selection, search and finding emphasis.
  void highlight() {
    final focus = state.focus;
    final typeId = state.selectedType;
    final searching = state.query.isNotEmpty;
    final finding = state.selectedFinding;
    layer.classList.toggle('focused', focus != null || typeId != null || searching || finding != null);
    layer.classList.toggle('finding', finding != null);

    _nodes.forEach((box, node) {
      final on = identical(box, state.hovered) || identical(box, state.selected);
      final same = focus != null
          ? state.sharesType(box, focus)
          : typeId != null
          ? state.hasType(box, typeId)
          : searching && state.matchesQuery(box);
      node.classList
        ..toggle('on', on)
        ..toggle('same', same && !on)
        ..toggle('sel', identical(box, state.selected));
    });

    for (final mark in _marks) {
      mark.remove();
    }
    _marks.clear();
    if (finding != null) {
      for (final occurrence in finding.occurrences) {
        final mark = el<web.HTMLElement>('div', cls: occurrence.isInline ? 'mark' : 'mark ok');
        mark.setAttribute('data-node', '${occurrence.node.id}');
        layer.appendChild(mark);
        _marks.add(mark);
      }
      _layoutMarks();
    }
  }

  void _layoutMarks() {
    for (final mark in _marks) {
      final id = int.parse(mark.getAttribute('data-node')!);
      final element = state.dom.elementOf(id);
      final rect = element == null ? null : pageRect(element);
      if (rect == null) {
        mark.style.display = 'none';
        continue;
      }
      mark.style
        ..display = ''
        ..left = px(rect.x)
        ..top = px(rect.y)
        ..width = px(rect.width)
        ..height = px(rect.height);
    }
  }

  set visible(bool value) => layer.style.display = value ? '' : 'none';
}
