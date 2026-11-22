import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Creates an element. A short name, because building the overlay's own DOM
/// by hand is most of what the views do.
T el<T extends web.HTMLElement>(
  String tag, {
  String? cls,
  String? text,
  String? title,
  Map<String, String>? attrs,
  List<web.Node>? children,
}) {
  final element = web.document.createElement(tag) as T;
  if (cls != null) element.className = cls;
  if (text != null) element.textContent = text;
  if (title != null) element.title = title;
  attrs?.forEach((name, value) => element.setAttribute(name, value));
  if (children != null) {
    for (final child in children) {
      element.appendChild(child);
    }
  }
  return element;
}

/// Listens for [type] on [target].
void on(
  web.EventTarget target,
  String type,
  void Function(web.Event event) handler, {
  bool capture = false,
  bool passive = false,
}) {
  target.addEventListener(type, handler.toJS, web.AddEventListenerOptions(capture: capture, passive: passive));
}

/// Removes every child of [element].
void clear(web.Element element) {
  var child = element.firstChild;
  while (child != null) {
    element.removeChild(child);
    child = element.firstChild;
  }
}

/// Runs [callback] before the next paint, at most once however often it is asked for.
class FrameTask {
  FrameTask(this.callback);

  final void Function() callback;
  bool _scheduled = false;

  void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    web.window.requestAnimationFrame(
      ((num _) {
        _scheduled = false;
        callback();
      }).toJS,
    );
  }
}

String px(num value) => '${value.toStringAsFixed(1)}px';
