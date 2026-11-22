/// The framework-neutral description of a rendered page: which components
/// produced which elements.
///
/// This library must stay free of `package:jaspr`, `package:web`, `dart:io`
/// and Flutter imports so that every collector and every consumer can share it.
library;

import 'dart:convert';

/// Version of the snapshot JSON schema.
const int snapshotVersion = 1;

/// What a node in the tree stands for.
enum NodeKind {
  /// An instance of a component class.
  component('c'),

  /// A rendered HTML element.
  element('e'),

  /// A rendered text node. Its content is truncated.
  text('t'),

  /// Output whose structure the collector cannot see, such as raw HTML.
  raw('r');

  const NodeKind(this.code);

  /// The one-letter code used in JSON.
  final String code;

  static NodeKind parse(String code) => values.firstWhere(
    (kind) => kind.code == code,
    orElse: () => throw FormatException('Unknown node kind "$code".'),
  );
}

/// Where a component class comes from.
enum Origin {
  /// Source that lives in the repository: the app and its local path packages.
  project,

  /// A hosted dependency.
  package,

  /// The UI framework itself.
  framework,

  /// Not known, for example when the server runs ahead-of-time compiled.
  unknown;

  static Origin parse(String name) => values.firstWhere((origin) => origin.name == name, orElse: () => unknown);
}

/// A component class that appears in a snapshot.
class ComponentType {
  ComponentType({
    required this.name,
    this.library,
    this.package,
    this.file,
    this.line,
    this.origin = Origin.unknown,
  });

  factory ComponentType.fromJson(Map<String, Object?> json) => ComponentType(
    name: json['name']! as String,
    library: json['library'] as String?,
    package: json['package'] as String?,
    file: json['file'] as String?,
    line: json['line'] as int?,
    origin: Origin.parse(json['origin'] as String? ?? 'unknown'),
  );

  /// Class name without type arguments.
  final String name;

  /// Library URI, such as `package:app/components/card.dart`.
  String? library;

  /// Package the library belongs to.
  String? package;

  /// Absolute path of the file that declares the class.
  String? file;

  /// One-based line of the class declaration.
  int? line;

  Origin origin;

  /// Identity of the class: two classes with the same name in different
  /// libraries are different types.
  String get id => library == null ? name : '$library#$name';

  /// `file:line` when the location is known.
  String? get location => file == null ? null : (line == null ? file : '$file:$line');

  Map<String, Object?> toJson() => {
    'name': name,
    'library': ?library,
    'package': ?package,
    'file': ?file,
    'line': ?line,
    'origin': origin.name,
  };
}

/// A rectangle in page coordinates (CSS pixels from the top-left of the document).
class Rect {
  const Rect(this.x, this.y, this.width, this.height);

  factory Rect.fromJson(List<Object?> json) => Rect(
    (json[0]! as num).toDouble(),
    (json[1]! as num).toDouble(),
    (json[2]! as num).toDouble(),
    (json[3]! as num).toDouble(),
  );

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get area => width * height;
  bool get isEmpty => width <= 0 || height <= 0;

  bool contains(double px, double py) => px >= x && px <= right && py >= y && py <= bottom;

  /// The smallest rectangle containing this one and [other].
  Rect union(Rect other) {
    final left = x < other.x ? x : other.x;
    final top = y < other.y ? y : other.y;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;
    return Rect(left, top, r - left, b - top);
  }

  List<Object?> toJson() => [_round(x), _round(y), _round(width), _round(height)];

  static num _round(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
  }

  @override
  String toString() => 'Rect($x, $y, $width, $height)';
}

/// One node of the page tree. See [NodeKind].
class AnatomyNode {
  AnatomyNode.component({required int this.type, this.key, this.client, List<AnatomyNode>? children})
    : kind = NodeKind.component,
      tag = null,
      domId = null,
      classes = const [],
      text = null,
      children = children ?? [];

  AnatomyNode.element({required String this.tag, this.domId, this.classes = const [], List<AnatomyNode>? children})
    : kind = NodeKind.element,
      type = null,
      key = null,
      client = null,
      text = null,
      children = children ?? [];

  AnatomyNode.text(String this.text)
    : kind = NodeKind.text,
      type = null,
      key = null,
      client = null,
      tag = null,
      domId = null,
      classes = const [],
      children = [];

  AnatomyNode.raw()
    : kind = NodeKind.raw,
      type = null,
      key = null,
      client = null,
      tag = null,
      domId = null,
      classes = const [],
      text = null,
      children = [];

  factory AnatomyNode.fromJson(Map<String, Object?> json) {
    final children = [
      for (final child in (json['n'] as List<Object?>?) ?? const <Object?>[])
        AnatomyNode.fromJson(child! as Map<String, Object?>),
    ];
    final node = switch (NodeKind.parse(json['k']! as String)) {
      NodeKind.component => AnatomyNode.component(
        type: json['y']! as int,
        key: json['key'] as String?,
        client: json['cl'] as String?,
        children: children,
      ),
      NodeKind.element => AnatomyNode.element(
        tag: json['g']! as String,
        domId: json['d'] as String?,
        classes: splitClasses(json['c'] as String?),
        children: children,
      ),
      NodeKind.text => AnatomyNode.text(json['x'] as String? ?? ''),
      NodeKind.raw => AnatomyNode.raw(),
    };
    if (json['r'] case final List<Object?> rect) node.rect = Rect.fromJson(rect);
    return node;
  }

  final NodeKind kind;

  /// Component only: index into [AnatomySnapshot.types].
  final int? type;

  /// Component only: the component's key, if it has one.
  final String? key;

  /// Component only: the client target name when this component is hydrated
  /// in the browser (a `@client` component in Jaspr).
  final String? client;

  /// Element only: lower-case tag name.
  final String? tag;

  /// Element only: the `id` attribute.
  final String? domId;

  /// Element only: class names in source order.
  final List<String> classes;

  /// Text only: the text, collapsed and truncated.
  final String? text;

  final List<AnatomyNode> children;

  /// Where the node is on the page. Only known in a browser.
  Rect? rect;

  /// Position in a depth-first walk of the snapshot. Assigned by [AnatomySnapshot].
  int id = -1;

  /// Assigned by [AnatomySnapshot].
  AnatomyNode? parent;

  bool get isComponent => kind == NodeKind.component;
  bool get isElement => kind == NodeKind.element;

  /// This node and everything below it, depth first.
  Iterable<AnatomyNode> get subtree sync* {
    yield this;
    for (final child in children) {
      yield* child.subtree;
    }
  }

  /// Everything below this node, depth first.
  Iterable<AnatomyNode> get descendants => subtree.skip(1);

  /// The nearest component above this node.
  AnatomyNode? get owner {
    for (var node = parent; node != null; node = node.parent) {
      if (node.isComponent) return node;
    }
    return null;
  }

  /// The components above this node, nearest first.
  Iterable<AnatomyNode> get owners sync* {
    for (var node = owner; node != null; node = node.owner) {
      yield node;
    }
  }

  /// The outermost non-component nodes this node renders: for an element that
  /// is the element itself, for a component it is what the component's output
  /// starts with, looking through nested components.
  Iterable<AnatomyNode> get hosts sync* {
    if (!isComponent) {
      yield this;
      return;
    }
    for (final child in children) {
      yield* child.hosts;
    }
  }

  Map<String, Object?> toJson() => {
    'k': kind.code,
    'y': ?type,
    'key': ?key,
    'cl': ?client,
    'g': ?tag,
    'd': ?domId,
    if (classes.isNotEmpty) 'c': classes.join(' '),
    'x': ?text,
    if (rect case final rect?) 'r': rect.toJson(),
    if (children.isNotEmpty) 'n': [for (final child in children) child.toJson()],
  };
}

/// The component tree of one rendered page.
class AnatomySnapshot {
  AnatomySnapshot({
    required this.types,
    required this.roots,
    this.url,
    this.framework = 'jaspr',
    this.version = snapshotVersion,
  }) {
    relink();
  }

  factory AnatomySnapshot.fromJson(Map<String, Object?> json) {
    final version = json['version'] as int? ?? 0;
    if (version != snapshotVersion) {
      throw FormatException('Unsupported anatomy snapshot version $version, expected $snapshotVersion.');
    }
    return AnatomySnapshot(
      version: version,
      framework: json['framework'] as String? ?? 'jaspr',
      url: json['url'] as String?,
      types: [
        for (final type in json['types']! as List<Object?>) ComponentType.fromJson(type! as Map<String, Object?>),
      ],
      roots: [
        for (final node in json['roots']! as List<Object?>) AnatomyNode.fromJson(node! as Map<String, Object?>),
      ],
    );
  }

  /// Parses the text produced by [encode].
  factory AnatomySnapshot.decode(String source) => AnatomySnapshot.fromJson(jsonDecode(source) as Map<String, Object?>);

  final int version;

  /// The UI framework the page was rendered with.
  final String framework;

  /// The URL of the page, as the collector saw it.
  final String? url;

  final List<ComponentType> types;
  final List<AnatomyNode> roots;

  final List<AnatomyNode> _byId = [];

  /// Reassigns [AnatomyNode.id] and [AnatomyNode.parent]. Call after changing the tree.
  void relink() {
    _byId.clear();
    void visit(AnatomyNode node, AnatomyNode? parent) {
      node
        ..id = _byId.length
        ..parent = parent;
      _byId.add(node);
      for (final child in node.children) {
        visit(child, node);
      }
    }

    for (final root in roots) {
      visit(root, null);
    }
  }

  /// Every node, depth first. A node's [AnatomyNode.id] is its index here.
  List<AnatomyNode> get nodes => _byId;

  Iterable<AnatomyNode> get components => _byId.where((node) => node.isComponent);

  Iterable<AnatomyNode> get elements => _byId.where((node) => node.isElement);

  /// The type of a component [node].
  ComponentType typeOf(AnatomyNode node) => types[node.type!];

  Map<String, Object?> toJson() => {
    'version': version,
    'framework': framework,
    'url': ?url,
    'types': [for (final type in types) type.toJson()],
    'roots': [for (final root in roots) root.toJson()],
  };

  /// Compact JSON without line breaks.
  String encode() => jsonEncode(toJson());
}

final RegExp _whitespace = RegExp(r'\s+');

/// Splits a `class` attribute into names.
List<String> splitClasses(String? classes) {
  if (classes == null) return const [];
  final names = classes.split(_whitespace).where((name) => name.isNotEmpty).toList();
  return names.isEmpty ? const [] : names;
}

/// Collapses whitespace in [text] and cuts it to [max] characters.
String truncateText(String text, [int max = 60]) {
  final collapsed = text.replaceAll(_whitespace, ' ').trim();
  return collapsed.length <= max ? collapsed : '${collapsed.substring(0, max - 1)}…';
}
