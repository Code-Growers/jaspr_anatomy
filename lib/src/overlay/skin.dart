import 'package:web/web.dart' as web;

import '../core/snapshot.dart';
import 'dom.dart';
import 'dom_map.dart';

/// Makes still copies of page elements for the layers view, so that a layer
/// can show what its component actually looks like.
///
/// A copy cannot rely on the page's stylesheets: it lives in the overlay's
/// shadow root, away from the selectors and ancestors that styled the
/// original. So every copied element carries its computed style inline, which
/// also freezes its size. Elements that belong to a nested component are left
/// out as invisible placeholders of the same size; they are drawn on that
/// component's own layer, and so every pixel appears exactly once.
class SkinBuilder {
  final Map<web.Element, String> _styles = Map.identity();

  /// Elements copied so far, to keep a huge page from freezing the browser.
  int copied = 0;

  static const int limit = 6000;

  bool get exhausted => copied >= limit;

  /// Copies [hosts] into a container for a layer whose top-left corner is at
  /// [origin] on the page. Subtrees rooted at an element in [omit] are
  /// replaced by placeholders.
  web.HTMLElement build(List<web.Element> hosts, Rect origin, Set<web.Element> omit) {
    final skin = el<web.HTMLElement>('div', cls: 'skin', attrs: {'inert': '', 'aria-hidden': 'true'});
    for (final host in hosts) {
      final rect = pageRect(host);
      if (rect == null) continue;
      final copy = _copy(host, omit);
      if (copy == null) continue;
      // The copy is placed by where the original is, not by the layout that
      // put it there.
      _appendStyle(
        copy,
        'position:absolute;left:${px(rect.x - origin.x)};top:${px(rect.y - origin.y)};'
        'width:${px(rect.width)};height:${px(rect.height)};box-sizing:border-box;margin:0;'
        'right:auto;bottom:auto;transform:none;translate:none;',
      );
      skin.appendChild(copy);
    }
    return skin;
  }

  static const Set<String> _skipped = {'script', 'style', 'link', 'template', 'noscript', 'meta', 'title', 'base'};
  static const Set<String> _boxesOnly = {'iframe', 'video', 'audio', 'object', 'embed', 'canvas'};

  web.Element? _copy(web.Element live, Set<web.Element> omit) {
    final tag = live.localName;
    if (_skipped.contains(tag)) return null;
    if (exhausted) return null;
    copied++;

    final omitted = omit.contains(live);
    // Custom elements would run their own code if they were cloned, and
    // embedded content would load again. A plain box of the same size stands
    // in for both.
    final plain = omitted || tag.contains('-') || _boxesOnly.contains(tag);
    final web.Element copy;
    if (plain) {
      copy = web.document.createElement('div');
    } else {
      copy = live.cloneNode(false) as web.Element;
      for (final name in const ['id', 'name', 'autofocus', 'autoplay', 'for', 'form', 'href', 'onclick']) {
        copy.removeAttribute(name);
      }
    }
    copy.setAttribute('style', _styleOf(live));

    if (omitted || plain) {
      final box = live.getBoundingClientRect();
      final inline = web.window.getComputedStyle(live).display.startsWith('inline');
      _appendStyle(
        copy,
        '${omitted ? 'visibility:hidden;' : ''}'
        '${inline ? 'display:inline-block;' : ''}'
        'width:${px(box.width)};height:${px(box.height)};box-sizing:border-box;',
      );
      return copy;
    }

    if (tag == 'input' || tag == 'textarea') {
      final type = live.getAttribute('type');
      // What was typed into a field is not part of the page's anatomy.
      if (type == 'password') copy.setAttribute('value', '');
      return copy;
    }

    final children = live.childNodes;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i)!;
      if (child.nodeType == web.Node.TEXT_NODE) {
        copy.appendChild(web.document.createTextNode(child.textContent ?? ''));
      } else if (child.nodeType == web.Node.ELEMENT_NODE) {
        final childCopy = _copy(child as web.Element, omit);
        if (childCopy != null) copy.appendChild(childCopy);
      }
    }
    return copy;
  }

  static void _appendStyle(web.Element element, String css) {
    element.setAttribute('style', '${element.getAttribute('style') ?? ''};$css');
  }

  /// The computed style of [live] as inline CSS.
  String _styleOf(web.Element live) => _styles[live] ??= _readStyle(live);

  static String _readStyle(web.Element live) {
    final computed = web.window.getComputedStyle(live);
    final buffer = StringBuffer();
    final count = computed.length;
    for (var i = 0; i < count; i++) {
      final name = computed.item(i);
      if (_ignored(name)) continue;
      final value = computed.getPropertyValue(name);
      if (value.isEmpty) continue;
      buffer
        ..write(name)
        ..write(':')
        ..write(value)
        ..write(';');
    }
    // A still picture: nothing moves, nothing reacts.
    buffer.write('animation:none;transition:none;');
    return buffer.toString();
  }

  /// Properties that say nothing new (logical twins of physical properties,
  /// vendor aliases) or that must not carry over (motion).
  static bool _ignored(String name) {
    if (name.startsWith('animation') || name.startsWith('transition')) return true;
    if (name.startsWith('-webkit-')) {
      return !(name.startsWith('-webkit-mask') ||
          name.startsWith('-webkit-text') ||
          name.startsWith('-webkit-line-clamp') ||
          name.startsWith('-webkit-box') ||
          name.startsWith('-webkit-background-clip'));
    }
    return name.contains('-block') || name.contains('-inline') || name == 'block-size' || name == 'inline-size';
  }
}

/// The background the page is painted on: the body's, or failing that the root's.
String pageBackground() {
  for (final element in [web.document.body, web.document.documentElement]) {
    if (element == null) continue;
    final color = web.window.getComputedStyle(element).backgroundColor;
    if (color.isNotEmpty && color != 'rgba(0, 0, 0, 0)' && color != 'transparent') return color;
  }
  return '#fff';
}
