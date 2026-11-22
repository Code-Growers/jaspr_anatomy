/// The overlay program. Compiled to JavaScript by `tool/build_overlay.dart`
/// and inlined by the server after the page's anatomy data.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../core/report.dart';
import '../core/snapshot.dart';
import '../protocol.dart';
import 'dom.dart';
import 'dom_map.dart';
import 'flat_view.dart';
import 'layers_view.dart';
import 'live.dart';
import 'panel.dart';
import 'state.dart';
import 'styles.dart';

const String _apiName = '__jasprAnatomy';

void main() {
  // The script can be parsed twice, for example when a hot reload brings a
  // fresh copy of the page. One overlay is enough.
  if (globalContext.has(_apiName)) return;
  final script = web.document.getElementById(anatomyDataId);
  // A client-mode app has no server snapshot; its client program describes it.
  if (script == null && !LiveTree.available) return;
  Overlay(script).start();
}

class Overlay {
  Overlay(this._script);

  /// The server's snapshot script, or null in a client-mode app.
  web.Element? _script;

  /// What the server rendered, aligned with the page.
  AnatomySnapshot? _server;
  DomMap? _serverDom;

  /// The live tree last shown, to tell whether anything changed.
  String? _liveJson;
  late final web.HTMLElement _host;
  late final OverlayState state;
  late final FlatView _flat;
  late final LayersView _layers;
  late final Panel _panel;
  late final web.HTMLElement _shield;
  late final FrameTask _measure = FrameTask(_remeasure);

  String _viewKey = '';
  ViewMode? _shownMode;
  String? get _root => _script?.getAttribute('data-root');

  /// The script element that started the overlay in a client-mode app.
  web.Element? get _ownScript => web.document.getElementById(anatomyOverlayId);

  void start() {
    if (_script case final script?) {
      _server = AnatomySnapshot.decode(script.textContent ?? '{}');
      // Read the page before the client script hydrates it: at this point the
      // DOM is exactly what the server rendered.
      _serverDom = DomMap.align(_server!, script);
    }
    final (snapshot, dom) = _describe();
    _keepOn();

    _host = el('div', attrs: {'id': '__jaspr_anatomy_host__'});
    _host.style.cssText = 'position:absolute;top:0;left:0;width:0;height:0;z-index:2147483647;';
    // Outside <body>, so replacing the body on hot reload leaves it alone.
    web.document.documentElement!.appendChild(_host);
    final shadow = _host.attachShadow(web.ShadowRootInit(mode: 'open'));
    final root = el<web.HTMLElement>('div', cls: 'root');
    shadow
      ..appendChild(el('style', text: overlayCss))
      ..appendChild(root);

    state = OverlayState(snapshot, dom);
    _flat = FlatView(state, root);
    _shield = el('div', cls: 'picking-shield');
    root.appendChild(_shield);
    _layers = LayersView(state, root);
    _panel = Panel(
      state,
      root,
      onTurnOff: _turnOff,
      onFront: () => _layers.front(),
      onResetCamera: () => _layers.reset(),
      snapshotJson: _snapshotJson,
      editorUrl: _script?.getAttribute('data-editor') ?? _ownScript?.getAttribute('data-editor') ?? defaultEditorUrl,
      projectRoot: _root,
    );

    state.listen(_render);
    on(web.document, liveEvent, (_) => _refresh());
    _listen();
    _exposeApi();
    _render();
  }

  /// Keeps anatomy on for the next navigation.
  void _keepOn() => web.document.cookie = '$anatomyCookie=1;path=/;SameSite=Lax';

  void _turnOff() {
    web.document.cookie = '$anatomyCookie=;path=/;max-age=0';
    final url = Uri.parse(web.window.location.href);
    if (url.queryParameters.containsKey(anatomyQuery)) {
      final query = Map.of(url.queryParameters)..remove(anatomyQuery);
      web.window.location.href = url.replace(queryParameters: query.isEmpty ? null : query).toString();
    } else {
      web.window.location.reload();
    }
  }

  void _render() {
    final mode = state.mode;
    final key = '${state.scopeName}|${state.maxDepth}|${state.textures}|${identityHashCode(state.snapshot)}';
    final rebuilt = key != _viewKey;
    final entered = mode != _shownMode;
    _viewKey = key;
    _shownMode = mode;

    if (rebuilt || (entered && mode != ViewMode.hidden)) state.measure();

    _flat.visible = mode == ViewMode.flat;
    if (mode == ViewMode.flat) {
      if (rebuilt || entered) {
        _flat.rebuild();
      } else {
        _flat.highlight();
      }
    }

    _layers
      ..visible = mode == ViewMode.layers
      ..dock(open: state.panelOpen, left: state.panelLeft);
    if (mode == ViewMode.layers) {
      if (rebuilt || entered) {
        _layers.rebuild();
      } else {
        _layers
          ..applySeparation()
          ..highlight();
      }
    }

    _shield.style.display = mode == ViewMode.flat && state.picking ? '' : 'none';
    _panel.render();
  }

  void _remeasure() {
    if (state.mode != ViewMode.flat) return;
    state.measure();
    _flat.layout();
  }

  /// Whether [event] happened inside the overlay's own interface.
  bool _isOwn(web.Event event) => event.target == _host;

  double _pageX(web.MouseEvent event) => event.clientX + web.window.scrollX;
  double _pageY(web.MouseEvent event) => event.clientY + web.window.scrollY;

  void _listen() {
    final document = web.document;

    on(web.window, 'scroll', (_) => _measure.schedule(), capture: true, passive: true);
    on(web.window, 'resize', (_) => _measure.schedule(), passive: true);
    on(web.window, 'load', (_) => _measure.schedule());

    // What is under the pointer, while the outlines are showing.
    web.MouseEvent? lastMove;
    final hover = FrameTask(() {
      final event = lastMove;
      if (event == null || state.mode != ViewMode.flat) return;
      state.hover(state.boxAt(_pageX(event), _pageY(event)));
    });
    on(
      document,
      'mousemove',
      (event) {
        if (state.mode != ViewMode.flat) return;
        if (_isOwn(event) && !state.picking) {
          // Over the panel: its rows decide what is highlighted.
          lastMove = null;
          return;
        }
        lastMove = event as web.MouseEvent;
        hover.schedule();
      },
      capture: true,
      passive: true,
    );
    on(document.documentElement!, 'mouseleave', (_) {
      lastMove = null;
      if (state.mode == ViewMode.flat) state.hover(null);
    });

    // Alt-click selects at any time; in pick mode a plain click does.
    on(document, 'click', (event) {
      if (state.mode != ViewMode.flat) return;
      final mouse = event as web.MouseEvent;
      if (_isOwn(event)) return;
      if (!mouse.altKey) return;
      event
        ..preventDefault()
        ..stopPropagation();
      state.select(state.boxAt(_pageX(mouse), _pageY(mouse)));
    }, capture: true);
    on(_shield, 'click', (event) {
      final mouse = event as web.MouseEvent;
      state.select(state.boxAt(_pageX(mouse), _pageY(mouse)));
    });

    on(document, 'keydown', (event) {
      final key = event as web.KeyboardEvent;
      if (key.altKey && key.shiftKey && key.code == 'KeyA') {
        key.preventDefault();
        state.toggleVisible();
      } else if (key.key == 'Escape' && state.mode != ViewMode.hidden) {
        if (state.picking || state.selected != null || state.selectedType != null || state.selectedFinding != null) {
          state.clearSelection();
        }
      }
    }, capture: true);

    // The page changes under us: layout shifts, client components re-render,
    // a hot reload swaps the body.
    var pending = false;
    void changed() {
      if (pending) return;
      pending = true;
      web.window.setTimeout(
        (() {
          pending = false;
          _pageChanged();
        }).toJS,
        120.toJS,
      );
    }

    web.MutationObserver(((JSArray<web.MutationRecord> records, web.MutationObserver observer) => changed()).toJS)
        .observe(document.documentElement!, web.MutationObserverInit(childList: true, subtree: true, attributes: true));
    web.ResizeObserver(
      ((JSArray<web.ResizeObserverEntry> entries, web.ResizeObserver observer) => _measure.schedule()).toJS,
    ).observe(document.documentElement!);
  }

  void _pageChanged() {
    final current = web.document.getElementById(anatomyDataId);
    if (current != null && current != _script) {
      // A new copy of the page arrived, with its own description.
      try {
        final snapshot = AnatomySnapshot.decode(current.textContent ?? '{}');
        _script = current;
        _server = snapshot;
        _serverDom = DomMap.align(snapshot, current);
        _liveJson = null;
        final (described, dom) = _describe();
        state.replace(described, dom);
      } on FormatException {
        // Keep showing the previous page's description.
      }
      return;
    }
    if (!_refresh()) _measure.schedule();
  }

  /// The page as the server rendered it, updated with the client program's
  /// live tree when the page has one.
  Described _describe() {
    final live = LiveTree.read();
    _liveJson = live?.json;
    if (live == null) {
      final empty = AnatomySnapshot(types: [], roots: []);
      return (_server ?? empty, _serverDom ?? DomMap.known(empty, {}));
    }
    return combine(_server, _serverDom, live);
  }

  /// Reads the live tree again. Returns whether the description changed.
  bool _refresh() {
    final live = LiveTree.read();
    if (live == null || live.json == _liveJson) return false;
    _liveJson = live.json;
    final (snapshot, dom) = combine(_server, _serverDom, live);
    state.refresh(snapshot, dom);
    return true;
  }

  /// The snapshot with the current position of every located node.
  String _snapshotJson() {
    state.measure();
    for (final node in state.snapshot.nodes) {
      node.rect = null;
      if (node.isElement) {
        if (state.dom.elementOf(node.id) case final element?) node.rect = pageRect(element);
      }
    }
    for (final box in state.boxes) {
      for (final node in box.chain) {
        node.rect = box.rect;
      }
    }
    return state.snapshot.encode();
  }

  void _exposeApi() {
    JSAny? parse(String json) => (globalContext['JSON']! as JSObject).callMethod<JSAny?>('parse'.toJS, json.toJS);

    final api = JSObject()
      ..['version'] = snapshotVersion.toJS
      // The page tree with positions, as a plain object.
      ..['snapshot'] = (() => parse(_snapshotJson())).toJS
      // The Markdown report of this page.
      ..['report'] = (() => renderReport(state.analysis, options: ReportOptions(root: _root)).toJS).toJS
      // The analysis of this page as a plain object.
      ..['analysis'] = (() => analysisToJson(state.analysis, root: _root).jsify()).toJS
      ..['show'] = (([JSString? mode]) {
        state.setMode(mode?.toDart == '3d' || mode?.toDart == 'layers' ? ViewMode.layers : ViewMode.flat);
      }).toJS
      ..['hide'] = (() => state.setMode(ViewMode.hidden)).toJS
      ..['off'] = _turnOff.toJS;
    globalContext[_apiName] = api;
  }
}
