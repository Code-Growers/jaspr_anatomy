import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../core/snapshot.dart';
import 'dom.dart';
import 'skin.dart';
import 'state.dart';

/// The page as a stack of layers: every box becomes a plane, lifted by how
/// deeply it is nested. Drag to turn, wheel to zoom, Shift-drag to move.
///
/// The scene holds only the overlay's own elements, built from the same
/// rectangles as the flat view, so nothing about the page can distort it.
class LayersView {
  LayersView(this.state, web.Node root)
    : stage = el('div', cls: 'stage'),
      world = el('div', cls: 'world'),
      _page = el('div', cls: 'page'),
      _hint = el('div', cls: 'hint', text: 'Drag to turn · Shift-drag to move · Wheel to zoom') {
    world.appendChild(_page);
    stage
      ..appendChild(world)
      ..appendChild(_hint);
    root.appendChild(stage);
    _listen();
  }

  final OverlayState state;
  final web.HTMLElement stage;
  final web.HTMLElement world;
  final web.HTMLElement _page;
  final web.HTMLElement _hint;

  final List<Box> _planeBoxes = [];
  final List<web.HTMLElement> _planes = [];

  // Camera.
  double _tilt = 58;
  double _turn = -32;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _focusX = 0;
  double _focusY = 0;
  bool _framed = false;

  /// Recreates one plane per drawn box.
  void rebuild() {
    for (final plane in _planes) {
      plane.remove();
    }
    _planes.clear();
    _planeBoxes.clear();

    final document = web.document.documentElement!;
    final width = math.max(document.scrollWidth, document.clientWidth).toDouble();
    final height = math.max(document.scrollHeight, document.clientHeight).toDouble();
    world.style
      ..width = px(width)
      ..height = px(height);
    _page.style
      ..width = px(width)
      ..height = px(height);

    final drawn = state.drawn.toList();
    final skins = state.textures ? SkinBuilder() : null;
    world.classList.toggle('skinned', skins != null);
    clear(_page);
    _page.style.background = skins == null ? '' : pageBackground();

    // Which drawn boxes sit directly inside which.
    final inside = <Box?, List<Box>>{};
    for (final box in drawn) {
      inside.putIfAbsent(box.parent, () => []).add(box);
    }
    Set<web.Element> hostsInside(Box? box) =>
        Set.identity()..addAll([for (final child in inside[box] ?? const <Box>[]) ...child.hosts]);

    if (skins != null) {
      // What no component claims (wrappers around the app) goes on the page itself.
      final outermost = [for (final root in state.snapshot.roots) ...state.dom.hostsOf(root)];
      _page.appendChild(skins.build(outermost, const Rect(0, 0, 0, 0), hostsInside(null)));
    }

    for (final box in drawn) {
      final rect = box.rect!;
      final plane = el<web.HTMLElement>(
        'div',
        cls: 'plane',
        attrs: {'data-i': '${_planes.length}'},
        children: [el('span', cls: 'tag', text: state.labelOf(box))],
      );
      plane.style
        ..left = px(rect.x)
        ..top = px(rect.y)
        ..width = px(rect.width)
        ..height = px(rect.height)
        ..setProperty('--h', '${state.hueOf(box)}')
        ..setProperty('--d', '${box.depth + 1}');
      if (skins != null) plane.insertBefore(skins.build(box.hosts, rect, hostsInside(box)), plane.firstChild);
      world.appendChild(plane);
      _planes.add(plane);
      _planeBoxes.add(box);
    }
    _hint.textContent = skins != null && skins.exhausted
        ? 'This page is too large to copy in full; some layers are empty. Narrow the view with Depth or the scope.'
        : 'Drag to turn · Shift-drag to move · Wheel to zoom';

    if (!_framed) frame();
    _applyCamera();
    highlight();
  }

  /// Points the camera at the part of the page that is on screen.
  void frame() {
    _framed = true;
    final viewWidth = web.window.innerWidth.toDouble();
    final viewHeight = web.window.innerHeight.toDouble();
    _focusX = web.window.scrollX + viewWidth / 2;
    _focusY = web.window.scrollY + viewHeight / 2;
    final stageWidth = stage.clientWidth == 0 ? viewWidth : stage.clientWidth.toDouble();
    _zoom = (stageWidth / viewWidth * 0.72).clamp(0.2, 1.2);
    _panX = 0;
    _panY = 0;
    _tilt = 58;
    _turn = -32;
  }

  /// Looks at the page straight on, as the flat view does.
  void front() {
    _tilt = 0;
    _turn = 0;
    _panX = 0;
    _panY = 0;
    _applyCamera();
  }

  void reset() {
    frame();
    _applyCamera();
  }

  void _applyCamera() {
    final centerX = stage.clientWidth / 2;
    final centerY = stage.clientHeight / 2;
    world.style
      ..setProperty('--sep', px(state.separation))
      ..setProperty('--zoom', _zoom.toStringAsFixed(4))
      ..transformOrigin = '${px(_focusX)} ${px(_focusY)}'
      ..transform =
          'translate(${px(centerX - _focusX + _panX)}, ${px(centerY - _focusY + _panY)}) '
          'scale(${_zoom.toStringAsFixed(4)}) '
          'rotateX(${_tilt.toStringAsFixed(2)}deg) rotateZ(${_turn.toStringAsFixed(2)}deg)';
  }

  /// Applies the separation between layers.
  void applySeparation() => world.style.setProperty('--sep', px(state.separation));

  /// Applies hover, selection and search emphasis.
  void highlight() {
    final focus = state.focus;
    final typeId = state.selectedType;
    final searching = state.query.isNotEmpty;
    world.classList.toggle('focused', focus != null || typeId != null || searching);
    for (var i = 0; i < _planes.length; i++) {
      final box = _planeBoxes[i];
      final on = identical(box, state.hovered) || identical(box, state.selected);
      final same = focus != null
          ? state.sharesType(box, focus)
          : typeId != null
          ? state.hasType(box, typeId)
          : searching && state.matchesQuery(box);
      _planes[i].classList
        ..toggle('on', on)
        ..toggle('same', same && !on)
        ..toggle('sel', identical(box, state.selected));
    }
  }

  set visible(bool value) {
    stage.style.display = value ? '' : 'none';
    if (value) _applyCamera();
  }

  /// Leaves room for the panel, wherever it is.
  void dock({required bool open, required bool left}) {
    final before = stage.className;
    stage.classList
      ..toggle('wide', !open)
      ..toggle('left', open && left);
    if (stage.className != before) _applyCamera();
  }

  Box? _boxFor(web.Event event) {
    final target = event.target;
    if (target == null || !target.isA<web.Element>()) return null;
    final plane = (target as web.Element).closest('.plane');
    final index = plane?.getAttribute('data-i');
    return index == null ? null : _planeBoxes[int.parse(index)];
  }

  void _listen() {
    var dragging = false;
    var moved = false;
    var lastX = 0.0;
    var lastY = 0.0;

    on(stage, 'pointerdown', (event) {
      final pointer = event as web.PointerEvent;
      if (pointer.button != 0) return;
      dragging = true;
      moved = false;
      lastX = pointer.clientX.toDouble();
      lastY = pointer.clientY.toDouble();
      stage.setPointerCapture(pointer.pointerId);
      stage.classList.add('dragging');
    });

    on(stage, 'pointermove', (event) {
      final pointer = event as web.PointerEvent;
      if (!dragging) {
        state.hover(_boxFor(event));
        return;
      }
      final dx = pointer.clientX - lastX;
      final dy = pointer.clientY - lastY;
      if (dx.abs() + dy.abs() > 2) moved = true;
      lastX = pointer.clientX.toDouble();
      lastY = pointer.clientY.toDouble();
      if (pointer.shiftKey) {
        _panX += dx;
        _panY += dy;
      } else {
        _turn += dx * 0.35;
        _tilt = (_tilt - dy * 0.35).clamp(0, 86);
      }
      _applyCamera();
    });

    void end(web.Event event) {
      if (!dragging) return;
      dragging = false;
      stage.classList.remove('dragging');
      // With the pointer captured by the stage, the event's target is the
      // stage itself. Ask the document what is really under the pointer.
      if (!moved) {
        final pointer = event as web.PointerEvent;
        // elementFromPoint exists on shadow roots as well as documents.
        final hit = (stage.getRootNode() as JSObject).callMethod<web.Element?>(
          'elementFromPoint'.toJS,
          pointer.clientX.toJS,
          pointer.clientY.toJS,
        );
        final index = hit?.closest('.plane')?.getAttribute('data-i');
        state.select(index == null ? null : _planeBoxes[int.parse(index)]);
      }
    }

    on(stage, 'pointerup', end);
    on(stage, 'pointercancel', (_) {
      dragging = false;
      stage.classList.remove('dragging');
    });
    on(stage, 'pointerleave', (_) {
      if (!dragging) state.hover(null);
    });

    on(stage, 'wheel', (event) {
      final wheel = event as web.WheelEvent;
      wheel.preventDefault();
      _zoom = (_zoom * math.exp(-wheel.deltaY * 0.0015)).clamp(0.08, 6);
      _applyCamera();
    });
  }
}
