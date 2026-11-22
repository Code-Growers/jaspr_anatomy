import 'dart:convert';

import 'package:web/web.dart' as web;

import '../core/analysis.dart';
import '../core/snapshot.dart';
import 'dom_map.dart';

/// What the overlay shows.
enum ViewMode {
  /// Nothing but the reopen button.
  hidden,

  /// Outlines over the real page.
  flat,

  /// Components as stacked layers.
  layers,
}

/// One outlined area of the page: a component, or several nested components
/// that render exactly the same elements (a wrapper and what it wraps).
class Box {
  Box(this.index, AnatomyNode first, this.hosts, this.parent)
    : chain = [first],
      depth = parent == null ? 0 : parent.depth + 1;

  /// Position in [OverlayState.boxes].
  final int index;

  /// The components of this box, outermost first.
  final List<AnatomyNode> chain;

  /// The page elements the components render.
  final List<web.Element> hosts;

  final Box? parent;

  /// Number of boxes around this one.
  final int depth;

  /// Where the box is on the page, or null when it has no area (a component
  /// that renders only text, or one whose elements have left the page).
  Rect? rect;

  AnatomyNode get node => chain.first;

  Iterable<Box> get ancestors sync* {
    for (var box = parent; box != null; box = box.parent) {
      yield box;
    }
  }
}

/// Everything the views draw from, and the one place that changes it.
class OverlayState {
  OverlayState(this.snapshot, this.dom) {
    _restore();
    rebuild();
  }

  AnatomySnapshot snapshot;
  DomMap dom;

  late Analysis analysis;
  final List<Box> boxes = [];
  final Map<int, Box> _boxByNode = {};

  ViewMode mode = ViewMode.flat;
  ViewMode _lastShown = ViewMode.flat;
  bool panelOpen = true;

  /// Which edge of the window the panel is docked to.
  bool panelLeft = false;
  String tab = 'tree';
  Scope scope = Scope.project;
  String scopeName = 'project';

  /// Deepest box level to draw, or null for all.
  int? maxDepth;
  String query = '';
  double separation = 64;

  /// Whether the layers show copies of the page's own pixels.
  bool textures = true;

  /// Whether the next click on the page selects instead of acting.
  bool picking = false;

  Box? hovered;
  Box? selected;

  /// [ComponentType.id] of a class picked from the component list.
  String? selectedType;
  MarkupFinding? selectedFinding;

  final List<void Function()> _listeners = [];

  void listen(void Function() listener) => _listeners.add(listener);

  void notify() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  // --- Derived data ----------------------------------------------------------

  /// Rebuilds [boxes] and [analysis] from the snapshot and the current scope.
  void rebuild() {
    analysis = Analysis([snapshot], scope: scope);
    boxes.clear();
    _boxByNode.clear();

    void visit(AnatomyNode node, Box? around) {
      var current = around;
      if (node.isComponent && scope.includes(snapshot.typeOf(node))) {
        final hosts = dom.hostsOf(node);
        if (around != null && hosts.isNotEmpty && _sameElements(around.hosts, hosts)) {
          around.chain.add(node);
        } else {
          current = Box(boxes.length, node, hosts, around);
          boxes.add(current);
        }
        _boxByNode[node.id] = current!;
      }
      for (final child in node.children) {
        visit(child, current);
      }
    }

    for (final root in snapshot.roots) {
      visit(root, null);
    }
    hovered = null;
    selected = null;
    selectedFinding = null;
    measure();
  }

  static bool _sameElements(List<web.Element> a, List<web.Element> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reads where every box currently is on the page.
  void measure() {
    for (final box in boxes) {
      box.rect = unionRect(box.hosts);
    }
  }

  ComponentType typeOf(AnatomyNode node) => snapshot.typeOf(node);

  Box? boxOf(AnatomyNode node) => _boxByNode[node.id];

  /// `Button › BaseButton`.
  String labelOf(Box box) => box.chain.map((node) => typeOf(node).name).join(' › ');

  /// The hue that stands for the class of [box] everywhere in the overlay.
  int hueOf(Box box) => hueFor(typeOf(box.node).id);

  bool matchesQuery(Box box) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return box.chain.any((node) => typeOf(node).name.toLowerCase().contains(needle));
  }

  bool withinDepth(Box box) => maxDepth == null || box.depth <= maxDepth!;

  /// Boxes that are drawn: within the depth limit and with an area.
  Iterable<Box> get drawn => boxes.where((box) => withinDepth(box) && box.rect != null && !box.rect!.isEmpty);

  int get deepest => boxes.fold(0, (deepest, box) => box.depth > deepest ? box.depth : deepest);

  /// Whether [box] contains a component of a class that [other] also contains.
  bool sharesType(Box box, Box other) {
    for (final a in box.chain) {
      for (final b in other.chain) {
        if (a.type == b.type) return true;
      }
    }
    return false;
  }

  bool hasType(Box box, String typeId) => box.chain.any((node) => typeOf(node).id == typeId);

  /// The box the views emphasise: what the pointer is on, else the selection.
  Box? get focus => hovered ?? selected;

  /// How many instances of the outermost class of [box] the page has.
  int instancesOf(Box box) => analysis.usageOf(typeOf(box.node).id)?.instances ?? 1;

  /// The deepest drawn box at page position ([x], [y]).
  Box? boxAt(double x, double y) {
    Box? best;
    for (final box in drawn) {
      if (!box.rect!.contains(x, y)) continue;
      if (best == null || box.depth > best.depth || (box.depth == best.depth && box.rect!.area < best.rect!.area)) {
        best = box;
      }
    }
    return best;
  }

  // --- Changes ---------------------------------------------------------------

  void setMode(ViewMode value) {
    if (value != ViewMode.hidden) _lastShown = value;
    mode = value;
    if (value == ViewMode.hidden) picking = false;
    _save();
    notify();
  }

  /// Shows the overlay again in the mode it was last shown in, or hides it.
  void toggleVisible() => setMode(mode == ViewMode.hidden ? _lastShown : ViewMode.hidden);

  /// What the small button does: bring back whatever is not showing.
  void reopen() {
    panelOpen = true;
    setMode(mode == ViewMode.hidden ? _lastShown : mode);
  }

  void setScope(String name) {
    scopeName = name;
    scope = switch (name) {
      'packages' => Scope.packages,
      'all' => Scope.all,
      _ => Scope.project,
    };
    maxDepth = null;
    rebuild();
    _save();
    notify();
  }

  void hover(Box? box) {
    if (identical(box, hovered)) return;
    hovered = box;
    notify();
  }

  void select(Box? box) {
    selected = box;
    selectedType = null;
    selectedFinding = null;
    picking = false;
    notify();
  }

  void selectType(String? typeId) {
    selectedType = typeId == selectedType ? null : typeId;
    selected = null;
    selectedFinding = null;
    notify();
  }

  void selectFinding(MarkupFinding? finding) {
    selectedFinding = identical(finding, selectedFinding) ? null : finding;
    selected = null;
    selectedType = null;
    notify();
  }

  void clearSelection() {
    selected = null;
    selectedType = null;
    selectedFinding = null;
    picking = false;
    notify();
  }

  void update(void Function() change) {
    change();
    _save();
    notify();
  }

  /// Replaces the page description, after the page itself was replaced.
  void replace(AnatomySnapshot nextSnapshot, DomMap nextDom) {
    snapshot = nextSnapshot;
    dom = nextDom;
    selectedType = null;
    rebuild();
    notify();
  }

  /// Replaces the page description after part of the page re-rendered,
  /// keeping what is selected where it still exists.
  void refresh(AnatomySnapshot nextSnapshot, DomMap nextDom) {
    final selectedHost = selected?.hosts.firstOrNull;
    final type = selectedType;
    snapshot = nextSnapshot;
    dom = nextDom;
    rebuild();
    if (selectedHost != null) {
      selected = boxes.where((box) => box.hosts.contains(selectedHost)).firstOrNull;
    }
    if (type != null && snapshot.types.any((t) => t.id == type)) selectedType = type;
    notify();
  }

  // --- Settings kept between page loads --------------------------------------

  static const String _storageKey = 'jaspr_anatomy';

  void _restore() {
    try {
      final stored = web.window.localStorage.getItem(_storageKey);
      if (stored == null) return;
      final json = jsonDecode(stored) as Map<String, Object?>;
      mode = switch (json['mode']) {
        'layers' => ViewMode.layers,
        'hidden' => ViewMode.hidden,
        _ => ViewMode.flat,
      };
      if (mode != ViewMode.hidden) _lastShown = mode;
      panelOpen = json['panel'] as bool? ?? true;
      panelLeft = json['left'] as bool? ?? false;
      textures = json['textures'] as bool? ?? true;
      tab = json['tab'] as String? ?? 'tree';
      separation = (json['separation'] as num?)?.toDouble() ?? 64;
      scopeName = json['scope'] as String? ?? 'project';
      scope = switch (scopeName) {
        'packages' => Scope.packages,
        'all' => Scope.all,
        _ => Scope.project,
      };
    } on Object {
      // Unreadable settings are the same as none.
    }
  }

  void _save() {
    try {
      web.window.localStorage.setItem(
        _storageKey,
        jsonEncode({
          'mode': mode.name,
          'panel': panelOpen,
          'left': panelLeft,
          'textures': textures,
          'tab': tab,
          'separation': separation,
          'scope': scopeName,
        }),
      );
    } on Object {
      // Storage can be unavailable; the overlay works without it.
    }
  }
}

/// A stable hue in 0–359 for [key], so a class keeps its colour across pages.
int hueFor(String key) {
  // Kept below 2^35 so the arithmetic is exact in JavaScript numbers.
  var hash = 7;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  // Spread neighbouring hashes around the wheel.
  return (hash % 360 * 137) % 360;
}
