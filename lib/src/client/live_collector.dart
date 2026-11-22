import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import '../core/snapshot.dart';
import '../protocol.dart';

/// The live component tree below one element, with the DOM node of every
/// element node.
class LiveCollection {
  LiveCollection(this.snapshot, this.nodes);

  final AnatomySnapshot snapshot;

  /// `nodes[i]` is the DOM node of `snapshot.nodes[i]`, or null for nodes
  /// that have none (components).
  final List<web.Node?> nodes;
}

/// Describes the client-side element tree below [root], as it is now.
///
/// The browser counterpart of the server collector. It sees what the server
/// cannot: components that `@client` components build after a click, and the
/// whole page of a client-mode app. Class names are what the compiler kept;
/// in a minified build the overlay recovers them from the server's snapshot.
LiveCollection collectLive(Element root) {
  final collector = _LiveCollector();
  final roots = <AnatomyNode>[];
  root.visitChildren((child) => collector.visit(child, roots));
  final snapshot = AnatomySnapshot(
    types: collector.types,
    roots: roots,
    url: '${web.window.location.pathname}${web.window.location.search}',
  );
  return LiveCollection(snapshot, [for (final node in snapshot.nodes) collector.domNodes[node]]);
}

class _LiveCollector {
  final List<ComponentType> types = [];
  final Map<String, int> _typeByName = {};

  /// Keyed by identity: [AnatomyNode] does not override equality.
  final Map<AnatomyNode, web.Node> domNodes = {};

  /// Inside the subtree of a `@client` component.
  bool _inIsland = false;

  /// The next component found is the root of a `@client` component.
  bool _islandRootPending = false;

  void visit(Element element, List<AnatomyNode> out) {
    final component = element.component;

    // Document components put their output into <head> or onto <html> and
    // <body>, not where the tree says.
    if (component is Document) return;

    if (component is ChildSlot) {
      // Jaspr mounts each @client component in a slot of the page's ClientApp.
      final wasInIsland = _inIsland;
      _inIsland = true;
      _islandRootPending = true;
      element.visitChildren((child) => visit(child, out));
      _inIsland = wasInIsland;
      _islandRootPending = false;
      return;
    }

    if (component is SlottedChildView && _inIsland) {
      // Server-rendered children of a @client component: their structure is
      // only in the server's snapshot.
      out.add(AnatomyNode.raw());
      return;
    }

    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      if (renderObject is DomRenderElement) {
        final dom = renderObject.node;
        final node = AnatomyNode.element(
          tag: dom.localName.toLowerCase(),
          domId: dom.id.isEmpty ? null : dom.id,
          classes: splitClasses(dom.getAttribute('class')),
        );
        domNodes[node] = dom;
        element.visitChildren((child) => visit(child, node.children));
        out.add(node);
      } else if (renderObject is DomRenderText) {
        final text = truncateText(renderObject.node.textContent ?? '');
        if (text.isNotEmpty) out.add(AnatomyNode.text(text));
      } else {
        // Fragments, slots and the root add no output of their own.
        element.visitChildren((child) => visit(child, out));
      }
      return;
    }

    if (_islandRootPending && component is Builder) {
      // Jaspr wraps each @client component in a keyed Builder.
      element.visitChildren((child) => visit(child, out));
      return;
    }

    final name = _stripTypeArguments(component.runtimeType.toString());
    if (isHtmlHelperName(name) && _rendersOneElement(element)) {
      element.visitChildren((child) => visit(child, out));
      return;
    }

    final islandRoot = _islandRootPending;
    _islandRootPending = false;
    final key = component.key?.toString();
    final node = AnatomyNode.component(
      type: _typeIndex(name),
      key: key == null ? null : truncateText(key, 40),
      client: islandRoot ? name : null,
    );
    element.visitChildren((child) => visit(child, node.children));
    out.add(node);
  }

  int _typeIndex(String name) => _typeByName[name] ??= () {
    types.add(
      ComponentType(
        name: name,
        origin: frameworkComponentNames.contains(name) || isHtmlHelperName(name) ? Origin.framework : Origin.unknown,
      ),
    );
    return types.length - 1;
  }();

  static bool _rendersOneElement(Element element) {
    Element? onlyChild;
    var count = 0;
    element.visitChildren((child) {
      onlyChild = child;
      count++;
    });
    return count == 1 && onlyChild is DomElement;
  }

  static String _stripTypeArguments(String name) {
    final index = name.indexOf('<');
    return index < 0 ? name : name.substring(0, index);
  }
}
