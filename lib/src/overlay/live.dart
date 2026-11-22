import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../core/snapshot.dart';
import '../protocol.dart';
import 'dom_map.dart';

/// The tree the app's client program reports through [liveApiName].
class LiveTree {
  LiveTree(this.json, this.snapshot, this.elements);

  /// The text it was decoded from: equal text means nothing changed.
  final String json;
  final AnatomySnapshot snapshot;

  /// DOM element of each element node, by [AnatomyNode.id].
  final Map<int, web.Element> elements;

  /// Whether the page's client program offers a live tree.
  static bool get available => globalContext.has(liveApiName);

  /// Asks the client program for its tree. Null when there is none or it
  /// cannot be read.
  static LiveTree? read() {
    try {
      final api = globalContext[liveApiName];
      if (api == null || !api.isA<JSObject>()) return null;
      final result = (api as JSObject).callMethod<JSAny?>('collect'.toJS);
      if (result == null || !result.isA<JSObject>()) return null;
      final object = result as JSObject;
      final json = (object['json']! as JSString).toDart;
      final nodes = (object['nodes']! as JSArray<JSAny?>).toDart;
      final snapshot = AnatomySnapshot.decode(json);
      final elements = <int, web.Element>{};
      for (final node in snapshot.nodes) {
        if (!node.isElement || node.id >= nodes.length) continue;
        final dom = nodes[node.id];
        if (dom != null && dom.isA<web.Element>()) elements[node.id] = dom as web.Element;
      }
      return LiveTree(json, snapshot, elements);
    } on Object {
      return null;
    }
  }
}

/// A description of the page and the DOM elements it refers to.
typedef Described = (AnatomySnapshot snapshot, DomMap dom);

/// Combines what the server rendered with what the browser has now.
///
/// Without a server snapshot (a client-mode app) the live tree is the whole
/// description. Otherwise each `@client` component of the server's snapshot
/// is replaced by the live subtree that renders the same page element, so
/// what the component built after load shows up. Class names, origins and
/// source locations come from the server wherever it knows the class: a
/// minified client calls them `minified:Xy`.
Described combine(AnatomySnapshot? server, DomMap? serverDom, LiveTree live) {
  final merger = _Merger(server, serverDom, live);
  return merger.run();
}

class _Merger {
  _Merger(this.server, this.serverDom, this.live);

  final AnatomySnapshot? server;
  final DomMap? serverDom;
  final LiveTree live;

  final List<ComponentType> types = [];
  final Map<String, int> _typeById = {};

  /// Element of each node of the result. Identity keys.
  final Map<AnatomyNode, web.Element> _elements = {};

  /// Server island → the live island that replaces it.
  final Map<AnatomyNode, AnatomyNode> _replacement = {};

  /// Live type index → server type index, learned from components that
  /// render the same element at the same depth.
  final Map<int, int> _learned = {};

  Described run() {
    final server = this.server;
    final List<AnatomyNode> roots;
    if (server == null) {
      roots = [for (final root in live.snapshot.roots) ..._copyLive(root)];
    } else {
      _matchIslands(server);
      roots = [for (final root in server.roots) ..._copyServer(root)];
    }
    final snapshot = AnatomySnapshot(types: types, roots: roots, url: server?.url ?? live.snapshot.url);
    return (
      snapshot,
      DomMap.known(snapshot, {
        for (final node in snapshot.nodes) node.id: ?_elements[node],
      }),
    );
  }

  // --- Matching --------------------------------------------------------------

  web.Element? _serverHost(AnatomyNode node) {
    for (final host in node.hosts) {
      if (serverDom!.elementOf(host.id) case final element?) return element;
    }
    return null;
  }

  web.Element? _liveHost(AnatomyNode node) {
    for (final host in node.hosts) {
      if (live.elements[host.id] case final element?) return element;
    }
    return null;
  }

  void _matchIslands(AnatomySnapshot server) {
    final liveIslands = live.snapshot.components.where((node) => node.client != null).toList();
    final byHost = {
      for (final island in liveIslands) ?_liveHost(island): island,
    };
    for (final island in server.components.where((node) => node.client != null)) {
      final host = _serverHost(island);
      final match = host == null ? null : byHost[host];
      // Server-rendered children inside the island are opaque to the client;
      // the server's description of it is the better one then.
      if (match == null || match.descendants.any((node) => node.kind == NodeKind.raw)) continue;
      _replacement[island] = match;
      _learnNames(island, match);
    }
  }

  /// Pairs the components of a server island with the live ones that render
  /// the same element, outermost first.
  void _learnNames(AnatomyNode serverIsland, AnatomyNode liveIsland) {
    Map<web.Element, List<AnatomyNode>> group(AnatomyNode root, web.Element? Function(AnatomyNode) hostOf) {
      final groups = <web.Element, List<AnatomyNode>>{};
      for (final node in root.subtree) {
        if (!node.isComponent) continue;
        final host = hostOf(node);
        if (host != null) (groups[host] ??= []).add(node);
      }
      return groups;
    }

    final serverGroups = group(serverIsland, _serverHost);
    final liveGroups = group(liveIsland, _liveHost);
    for (final MapEntry(key: host, value: liveChain) in liveGroups.entries) {
      final serverChain = serverGroups[host];
      if (serverChain == null) continue;
      for (var i = 0; i < liveChain.length && i < serverChain.length; i++) {
        _learned[liveChain[i].type!] ??= serverChain[i].type!;
      }
    }
  }

  // --- Copying ---------------------------------------------------------------

  int _serverType(int index) {
    final type = server!.types[index];
    return _typeById[type.id] ??= () {
      types.add(type);
      return types.length - 1;
    }();
  }

  /// The result's type for live type [index], or null when the class is a
  /// minified one the server never named.
  int? _liveType(int index) {
    if (_learned[index] case final serverIndex?) return _serverType(serverIndex);
    final type = live.snapshot.types[index];
    if (server case final server?) {
      if (!isMinifiedName(type.name)) {
        for (var i = 0; i < server.types.length; i++) {
          if (server.types[i].name == type.name) return _serverType(i);
        }
      }
    }
    if (isMinifiedName(type.name)) return null;
    return _typeById[type.id] ??= () {
      types.add(type);
      return types.length - 1;
    }();
  }

  int _minifiedType(int index) {
    final type = live.snapshot.types[index];
    return _typeById['live#${type.name}'] ??= () {
      types.add(ComponentType(name: type.name));
      return types.length - 1;
    }();
  }

  List<AnatomyNode> _copyServer(AnatomyNode node) {
    if (_replacement[node] case final replacement?) return _copyLive(replacement, client: node.client);
    final copy = _shallow(node, type: node.isComponent ? _serverType(node.type!) : null);
    if (node.isElement) {
      if (serverDom!.elementOf(node.id) case final element?) _elements[copy] = element;
    }
    for (final child in node.children) {
      copy.children.addAll(_copyServer(child));
    }
    return [copy];
  }

  List<AnatomyNode> _copyLive(AnatomyNode node, {String? client}) {
    if (node.isComponent) {
      final type = _liveType(node.type!);
      if (type == null && node.children.length == 1 && node.children.single.isElement && client == null) {
        // A minified class the server never rendered, wrapping one element:
        // almost always one of Jaspr's HTML helpers.
        return _copyLive(node.children.single);
      }
      final copy = _shallow(node, type: type ?? _minifiedType(node.type!), client: client ?? node.client);
      for (final child in node.children) {
        copy.children.addAll(_copyLive(child));
      }
      return [copy];
    }
    final copy = _shallow(node);
    if (live.elements[node.id] case final element?) _elements[copy] = element;
    for (final child in node.children) {
      copy.children.addAll(_copyLive(child));
    }
    return [copy];
  }

  static AnatomyNode _shallow(AnatomyNode node, {int? type, String? client}) => switch (node.kind) {
    NodeKind.component => AnatomyNode.component(type: type!, key: node.key, client: client ?? node.client),
    NodeKind.element => AnatomyNode.element(tag: node.tag!, domId: node.domId, classes: node.classes),
    NodeKind.text => AnatomyNode.text(node.text ?? ''),
    NodeKind.raw => AnatomyNode.raw(),
  };
}
