/// Reuse analysis over one or more [AnatomySnapshot]s.
///
/// Pure Dart: runs in the browser overlay, in command-line tools and in tests.
library;

import 'snapshot.dart';

/// Which component classes count as the app's own.
class Scope {
  const Scope(this.origins);

  /// Components written in the repository. Types of unknown origin are
  /// included, because a server that cannot report origins knows nothing else.
  static const Scope project = Scope({Origin.project, Origin.unknown});

  /// Also components from hosted packages.
  static const Scope packages = Scope({Origin.project, Origin.unknown, Origin.package});

  /// Every component, framework internals included.
  static const Scope all = Scope({Origin.project, Origin.unknown, Origin.package, Origin.framework});

  final Set<Origin> origins;

  bool includes(ComponentType type) => origins.contains(type.origin);
}

/// How one component class is used across the analysed pages.
class TypeUsage {
  TypeUsage(this.type);

  final ComponentType type;

  /// Number of instances on all pages.
  int instances = 0;

  /// Elements whose nearest in-scope component is of this type: the markup
  /// this class writes itself rather than delegating to other components.
  int ownElements = 0;

  /// Instances per page URL.
  final Map<String, int> perPage = {};

  /// The in-scope components that directly contain instances of this type,
  /// by type name. The empty string stands for the page root.
  final Map<String, int> containers = {};

  int get pages => perPage.length;
}

/// Totals for one page.
class PageSummary {
  PageSummary({
    required this.url,
    required this.elements,
    required this.components,
    required this.types,
    required this.reusedElements,
    required this.unownedElements,
  });

  final String url;

  /// Rendered elements on the page.
  final int elements;

  /// In-scope component instances.
  final int components;

  /// Distinct in-scope component classes.
  final int types;

  /// Elements written by a class that has more than one instance in the analysed set.
  final int reusedElements;

  /// Elements that no in-scope component contains.
  final int unownedElements;

  /// Share of the page's elements that come from reused components, 0–1.
  double get reuseShare => elements == 0 ? 0 : reusedElements / elements;
}

/// Why a group of identical markup is worth a look.
enum FindingKind {
  /// Inline markup has the same structure as what an existing component renders.
  duplicatesComponent,

  /// Two or more component classes render the same structure.
  twinComponents,

  /// The same inline markup appears in several places and no component renders it.
  repeatedInline,
}

/// One place where repeated markup occurs.
class Occurrence {
  Occurrence({
    required this.page,
    required this.node,
    required this.owner,
    required this.producers,
    this.ownerNode,
  });

  /// URL of the page.
  final String page;

  /// The root element of the repeated markup.
  final AnatomyNode node;

  /// Name of the nearest in-scope component containing the markup, or null.
  final String? owner;

  /// The instance [owner] names.
  final AnatomyNode? ownerNode;

  /// Names of the in-scope components whose whole output is this element,
  /// innermost first. Empty when the markup is written inline.
  final List<String> producers;

  bool get isInline => producers.isEmpty;
}

/// A structure that repeats in a way that suggests a missing or missed component.
///
/// Two pieces of markup count as the same structure when their root elements
/// and the direct children of those roots have the same tags and classes.
/// What sits deeper may differ, as it does between two uses of one component.
class MarkupFinding {
  MarkupFinding({
    required this.kind,
    required this.shape,
    required this.minElements,
    required this.maxElements,
    required this.identical,
    required this.occurrences,
    required this.components,
  });

  final FindingKind kind;

  /// A short description of the structure, such as
  /// `div.card > (h3.card-title + div.card-body)`.
  final String shape;

  /// Number of elements in the smallest occurrence.
  final int minElements;

  /// Number of elements in the largest occurrence.
  final int maxElements;

  /// Whether every occurrence has exactly the same elements all the way down.
  final bool identical;

  final List<Occurrence> occurrences;

  /// Names of the components that render this structure.
  final List<String> components;

  Iterable<Occurrence> get inline => occurrences.where((occurrence) => occurrence.isInline);

  /// In-scope components that contain the inline copies, with counts. The
  /// empty string stands for markup outside any component.
  Map<String, int> get inlineOwners {
    final owners = <String, int>{};
    for (final occurrence in inline) {
      owners.update(occurrence.owner ?? '', (count) => count + 1, ifAbsent: () => 1);
    }
    return owners;
  }

  Set<String> get pages => {for (final occurrence in occurrences) occurrence.page};
}

/// The reuse picture of a set of pages.
class Analysis {
  /// Analyses [snapshots]. Inline markup is reported when every copy has at
  /// least [minSize] elements and it appears at least [minCount] times; markup
  /// that matches what an existing component renders is reported at any size.
  Analysis(List<AnatomySnapshot> snapshots, {this.scope = Scope.project, this.minSize = 3, this.minCount = 2})
    : snapshots = List.unmodifiable(snapshots) {
    _run();
  }

  final List<AnatomySnapshot> snapshots;
  final Scope scope;
  final int minSize;
  final int minCount;

  /// One entry per snapshot, in the same order.
  final List<PageSummary> pages = [];

  /// In-scope component classes, most used first.
  final List<TypeUsage> types = [];

  /// Repeated markup, most significant first.
  final List<MarkupFinding> findings = [];

  final Map<String, TypeUsage> _usageById = {};
  final Map<AnatomyNode, TypeUsage?> _ownerUsage = Map.identity();

  /// For every element: the nearest in-scope component instance above it.
  final Map<AnatomyNode, AnatomyNode?> _ownerNode = Map.identity();

  /// Usage of the class with [ComponentType.id] [id], if it is in scope and appears.
  TypeUsage? usageOf(String id) => _usageById[id];

  int get totalElements => pages.fold(0, (sum, page) => sum + page.elements);
  int get totalInstances => pages.fold(0, (sum, page) => sum + page.components);
  int get reusedElements => pages.fold(0, (sum, page) => sum + page.reusedElements);

  /// Share of all elements that come from components with more than one instance, 0–1.
  double get reuseShare => totalElements == 0 ? 0 : reusedElements / totalElements;

  /// Classes with a single instance, ordered by how much markup they write
  /// themselves. Large entries are where inline markup accumulates.
  List<TypeUsage> get oneOffs =>
      types.where((usage) => usage.instances == 1 && usage.ownElements > 0).toList()
        ..sort((a, b) => b.ownElements.compareTo(a.ownElements));

  void _run() {
    for (final snapshot in snapshots) {
      _countUsage(snapshot);
    }
    for (final snapshot in snapshots) {
      pages.add(_summarize(snapshot));
    }
    types
      ..addAll(_usageById.values)
      ..sort((a, b) {
        final byCount = b.instances.compareTo(a.instances);
        return byCount != 0 ? byCount : a.type.name.compareTo(b.type.name);
      });
    findings.addAll(_findRepeats());
  }

  String _pageName(AnatomySnapshot snapshot) => snapshot.url ?? 'page ${snapshots.indexOf(snapshot) + 1}';

  bool _inScope(AnatomySnapshot snapshot, AnatomyNode node) =>
      node.isComponent && scope.includes(snapshot.typeOf(node));

  /// The nearest in-scope component above [node].
  AnatomyNode? _scopedOwner(AnatomySnapshot snapshot, AnatomyNode node) {
    for (var owner = node.owner; owner != null; owner = owner.owner) {
      if (_inScope(snapshot, owner)) return owner;
    }
    return null;
  }

  void _countUsage(AnatomySnapshot snapshot) {
    final page = _pageName(snapshot);
    for (final node in snapshot.nodes) {
      if (_inScope(snapshot, node)) {
        final type = snapshot.typeOf(node);
        final usage = _usageById.putIfAbsent(type.id, () => TypeUsage(type));
        usage.instances++;
        usage.perPage.update(page, (count) => count + 1, ifAbsent: () => 1);
        final container = _scopedOwner(snapshot, node);
        final containerName = container == null ? '' : snapshot.typeOf(container).name;
        usage.containers.update(containerName, (count) => count + 1, ifAbsent: () => 1);
      } else if (node.isElement) {
        final owner = _scopedOwner(snapshot, node);
        final usage = owner == null
            ? null
            : _usageById.putIfAbsent(
                snapshot.typeOf(owner).id,
                () => TypeUsage(snapshot.typeOf(owner)),
              );
        usage?.ownElements++;
        _ownerUsage[node] = usage;
        _ownerNode[node] = owner;
      }
    }
  }

  PageSummary _summarize(AnatomySnapshot snapshot) {
    var elements = 0;
    var reused = 0;
    var unowned = 0;
    var components = 0;
    final typeIds = <String>{};
    for (final node in snapshot.nodes) {
      if (node.isElement) {
        elements++;
        final usage = _ownerUsage[node];
        if (usage == null) {
          unowned++;
        } else if (usage.instances > 1) {
          reused++;
        }
      } else if (_inScope(snapshot, node)) {
        components++;
        typeIds.add(snapshot.typeOf(node).id);
      }
    }
    return PageSummary(
      url: _pageName(snapshot),
      elements: elements,
      components: components,
      types: typeIds.length,
      reusedElements: reused,
      unownedElements: unowned,
    );
  }

  // --- Repeated markup -------------------------------------------------------

  final Map<String, int> _signatureIds = {};

  int _intern(String signature) => _signatureIds.putIfAbsent(signature, () => _signatureIds.length);

  /// The element children of [node], looking through components.
  static Iterable<AnatomyNode> _elementChildren(AnatomyNode node) sync* {
    for (final child in node.children) {
      if (child.isElement) {
        yield child;
      } else if (child.isComponent) {
        yield* _elementChildren(child);
      } else if (child.kind == NodeKind.raw) {
        yield child;
      }
    }
  }

  static String _label(AnatomyNode node) {
    if (node.kind == NodeKind.raw) return '?';
    final classes = [...node.classes]..sort();
    return '${node.tag}.${classes.join('.')}';
  }

  List<MarkupFinding> _findRepeats() {
    final groups = <int, _Group>{};

    for (final snapshot in snapshots) {
      final page = _pageName(snapshot);

      // Returns (exact signature id, number of elements) of the subtree at [node].
      (int, int) visit(AnatomyNode node) {
        if (node.kind == NodeKind.raw) return (_intern('?'), 0);
        final children = _elementChildren(node).toList();
        final childIds = <int>[];
        var size = 1;
        for (final child in children) {
          final (id, childSize) = visit(child);
          childIds.add(id);
          size += childSize;
        }
        final label = _label(node);
        final exact = _intern('$label[${childIds.join(',')}]');
        // The grouping signature only looks one level down.
        final shallow = _intern('~$label{${children.map(_label).join(',')}}');
        groups
            .putIfAbsent(shallow, _Group.new)
            .add(
              Occurrence(
                page: page,
                node: node,
                owner: switch (_ownerNode[node]) {
                  final owner? => snapshot.typeOf(owner).name,
                  null => null,
                },
                ownerNode: _ownerNode[node],
                producers: _producers(snapshot, node),
              ),
              exact: exact,
              size: size,
            );
        return (exact, size);
      }

      for (final root in snapshot.roots) {
        for (final element in root.isElement ? [root] : _elementChildren(root)) {
          if (element.isElement) visit(element);
        }
      }
    }

    // Largest structures first, so that a structure that is reported or
    // explained hides the smaller structures inside it.
    final ordered = groups.values.where((group) => group.occurrences.length >= minCount).toList()
      ..sort((a, b) => b.maxSize.compareTo(a.maxSize));

    // For an element inside a structure that was reported or explained: the
    // root of the innermost such structure.
    final coverRoot = Map<AnatomyNode, AnatomyNode>.identity();
    final findings = <MarkupFinding>[];

    for (final group in ordered) {
      final occurrences = group.occurrences;
      // A structure that appears once inside each copy of a larger repeated
      // structure repeats only because the larger one does. Several copies
      // inside one of them is repetition in its own right.
      final roots = Set<AnatomyNode>.identity();
      if (occurrences.every((occurrence) {
        final root = coverRoot[occurrence.node];
        return root != null && roots.add(root);
      })) {
        continue;
      }

      // Components that render this structure, and those that do so everywhere it appears.
      Set<String>? common;
      final producing = <String>{};
      for (final occurrence in occurrences) {
        producing.addAll(occurrence.producers);
        final names = occurrence.producers.toSet();
        common = common == null ? names : common.intersection(names);
      }
      final explained = common != null && common.isNotEmpty;
      final inlineCount = occurrences.where((occurrence) => occurrence.isInline).length;
      final hasClass = occurrences.first.node.classes.isNotEmpty;
      // Unstyled structure such as table rows or plain lists is content, not a
      // component waiting to be extracted.
      final styled = hasClass || _elementChildren(occurrences.first.node).any((child) => child.classes.isNotEmpty);
      final substantial = group.minSize >= minSize && styled;

      // Inline markup that shows up once in every instance of one component
      // (or once per page, outside any component) is that component being
      // reused, not markup being repeated.
      var oncePerOwner = false;
      if (!explained && producing.isEmpty) {
        final perOwner = <Object, int>{};
        final ownerTypes = <String>{};
        for (final occurrence in occurrences) {
          perOwner.update(occurrence.ownerNode ?? occurrence.page, (count) => count + 1, ifAbsent: () => 1);
          ownerTypes.add(occurrence.owner ?? '');
        }
        oncePerOwner = ownerTypes.length == 1 && perOwner.values.every((count) => count == 1);
      }

      FindingKind? kind;
      if (explained || oncePerOwner) {
        // Every occurrence comes from the same component: reuse is working.
        kind = null;
      } else if (inlineCount > 0 && producing.isNotEmpty) {
        if (hasClass || group.minSize >= minSize) kind = FindingKind.duplicatesComponent;
      } else if (inlineCount == 0) {
        if (hasClass || group.minSize >= minSize) kind = FindingKind.twinComponents;
      } else if (substantial) {
        kind = FindingKind.repeatedInline;
      }

      if (kind != null || explained || oncePerOwner) {
        // What the same component instance wrote inside these occurrences
        // repeats for the same reason. Elements of nested components do not:
        // two cards being alike says nothing about what was put into them.
        for (final occurrence in occurrences) {
          final owner = _ownerNode[occurrence.node];
          for (final node in occurrence.node.descendants) {
            if (node.isElement && identical(_ownerNode[node], owner)) coverRoot[node] = occurrence.node;
          }
        }
      }
      if (kind == null) continue;

      findings.add(
        MarkupFinding(
          kind: kind,
          shape: describeShape(occurrences.first.node, depth: 1),
          minElements: group.minSize,
          maxElements: group.maxSize,
          identical: group.exactIds.length == 1,
          occurrences: occurrences,
          components: producing.toList()..sort(),
        ),
      );
    }

    // Markup copied between different components is the most actionable, so
    // it comes first; then whatever repeats most.
    findings.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      final bySpread = b.inlineOwners.length.compareTo(a.inlineOwners.length);
      if (bySpread != 0) return bySpread;
      final byCount = b.occurrences.length.compareTo(a.occurrences.length);
      return byCount != 0 ? byCount : b.minElements.compareTo(a.minElements);
    });
    return findings;
  }

  /// In-scope components whose entire output is [element], innermost first.
  List<String> _producers(AnatomySnapshot snapshot, AnatomyNode element) {
    final producers = <String>[];
    AnatomyNode child = element;
    for (var parent = element.parent; parent != null && parent.isComponent; parent = parent.parent) {
      // A component that renders several siblings is not "this element".
      if (parent.children.length != 1 || !identical(parent.children.single, child)) break;
      if (_inScope(snapshot, parent)) producers.add(snapshot.typeOf(parent).name);
      child = parent;
    }
    return producers;
  }
}

class _Group {
  final List<Occurrence> occurrences = [];
  final Set<int> exactIds = {};
  int minSize = 1 << 30;
  int maxSize = 0;

  void add(Occurrence occurrence, {required int exact, required int size}) {
    occurrences.add(occurrence);
    exactIds.add(exact);
    if (size < minSize) minSize = size;
    if (size > maxSize) maxSize = size;
  }
}

/// A short, CSS-like description of the element at [node] and its children.
String describeShape(AnatomyNode node, {int depth = 2, int maxChildren = 4}) {
  String label(AnatomyNode element) {
    if (element.kind == NodeKind.raw) return '(raw html)';
    final classes = element.classes.take(3).map((name) => '.$name').join();
    final more = element.classes.length > 3 ? '…' : '';
    return '${element.tag}$classes$more';
  }

  String describe(AnatomyNode element, int remaining) {
    final children = Analysis._elementChildren(element).toList();
    if (children.isEmpty || remaining == 0) return label(element);
    final shown = children.take(maxChildren).map((child) => describe(child, remaining - 1)).toList();
    if (children.length > maxChildren) shown.add('… ${children.length - maxChildren} more');
    final inner = shown.join(' + ');
    return children.length == 1 ? '${label(element)} > $inner' : '${label(element)} > ($inner)';
  }

  return describe(node, depth);
}
