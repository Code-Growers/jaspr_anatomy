import 'package:jaspr/server.dart';

import '../core/snapshot.dart';
import 'type_registry.dart';

/// Builds an [AnatomySnapshot] from the finished server-side element tree below [root].
///
/// Call this once the tree is complete, which on the server means inside a
/// [RenderAdapter]'s `prepare`.
AnatomySnapshot collectSnapshot(Element root, ServerAppBinding binding) {
  final collector = _Collector(binding);
  final roots = <AnatomyNode>[];
  root.visitChildren((child) => collector.visit(child, roots));
  return AnatomySnapshot(types: collector.registry.types, roots: roots, url: binding.currentUrl);
}

class _Collector {
  _Collector(this.binding);

  final ServerAppBinding binding;
  final TypeRegistry registry = TypeRegistry();

  late final Map<Type, ClientTarget>? _clients = _readClients();

  Map<Type, ClientTarget>? _readClients() {
    try {
      return binding.options.clients;
    } on Object {
      // Options are not initialized in some test setups.
      return null;
    }
  }

  void visit(Element element, List<AnatomyNode> out) {
    final component = element.component;

    // Document components move their output into <head>, <html> or <body>
    // attributes, so it does not appear where the tree says it would.
    if (component is Document) return;

    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      if (renderObject is MarkupRenderElement) {
        final node = AnatomyNode.element(
          tag: renderObject.tag.toLowerCase(),
          domId: renderObject.id ?? renderObject.attributes?['id'],
          classes: splitClasses(renderObject.classes),
        );
        element.visitChildren((child) => visit(child, node.children));
        out.add(node);
      } else if (renderObject is MarkupRenderText) {
        if (renderObject.rawHtml) {
          if (renderObject.text.trim().isNotEmpty) out.add(AnatomyNode.raw());
        } else {
          final text = truncateText(renderObject.text);
          if (text.isNotEmpty) out.add(AnatomyNode.text(text));
        }
      } else {
        // Fragments and other grouping render objects add no output of their own.
        element.visitChildren((child) => visit(child, out));
      }
      return;
    }

    final type = registry.lookup(component.runtimeType);
    if (_isHtmlHelper(type, element)) {
      element.visitChildren((child) => visit(child, out));
      return;
    }

    final key = component.key?.toString();
    final node = AnatomyNode.component(
      type: registry.indexOf(component.runtimeType),
      key: key == null ? null : truncateText(key, 40),
      client: _clients?[component.runtimeType]?.name,
    );
    element.visitChildren((child) => visit(child, node.children));
    out.add(node);
  }

  /// Whether [element] is one of Jaspr's HTML helper components (`div(...)`),
  /// which only exist to create the element below them.
  bool _isHtmlHelper(ComponentType type, Element element) {
    final library = type.library;
    final looksLikeHelper = library != null ? isHtmlHelperLibrary(library) : isHtmlHelperName(type.name);
    if (!looksLikeHelper) return false;
    Element? onlyChild;
    var count = 0;
    element.visitChildren((child) {
      onlyChild = child;
      count++;
    });
    return count == 1 && onlyChild is DomElement;
  }
}
