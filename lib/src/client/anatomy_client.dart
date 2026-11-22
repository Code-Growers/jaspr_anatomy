import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:jaspr/client.dart';
import 'package:web/web.dart' as web;

import '../protocol.dart';
import '../server/overlay_bundle.g.dart';
import 'live_collector.dart';

/// Makes the component structure of the page below it inspectable.
///
/// In the browser, wrap the root passed to `runApp` in it:
///
/// ```dart
/// runApp(Anatomy(child: ClientApp()));   // server mode
/// runApp(Anatomy(child: App()));         // client mode
/// ```
///
/// The overlay can then follow what the browser builds after the page has
/// loaded. In a client-mode app it also adds the overlay itself, because no
/// server is there to do it. Nothing is added to the app's own markup.
class Anatomy extends StatefulComponent {
  const Anatomy({
    required this.child,
    this.enabled = kDebugMode,
    this.hotkey = true,
    this.editorUrl = defaultEditorUrl,
    super.key,
  });

  /// The part of the page to describe.
  final Component child;

  /// Whether the tool is available at all. Defaults to [kDebugMode], which is
  /// false in release builds of the client.
  final bool enabled;

  /// Whether a page that did not ask for anatomy listens for Alt+Shift+A.
  final bool hotkey;

  /// Link template the overlay uses to open a source file.
  final String editorUrl;

  @override
  State<Anatomy> createState() => _AnatomyState();
}

class _AnatomyState extends State<Anatomy> {
  @override
  void initState() {
    super.initState();
    if (component.enabled) _LiveApi.attach(this);
  }

  @override
  void didUpdateComponent(Anatomy oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.enabled) _LiveApi.changed(context.binding);
  }

  @override
  void dispose() {
    _LiveApi.detach(this);
    super.dispose();
  }

  @override
  Component build(BuildContext context) => component.child;
}

/// The [liveApiName] global, shared by every [Anatomy] on the page.
abstract final class _LiveApi {
  static final List<_AnatomyState> _states = [];
  static bool _installed = false;
  static bool _started = false;
  static bool _notifyScheduled = false;

  static void attach(_AnatomyState state) {
    _states.add(state);
    if (!_installed) {
      _installed = true;
      globalContext[liveApiName] = JSObject()
        ..['version'] = liveApiVersion.toJS
        ..['collect'] = _collect.toJS;
    }
    changed(state.context.binding);
  }

  static void detach(_AnatomyState state) => _states.remove(state);

  /// Tells the overlay to read the tree again once the current frame is built.
  static void changed(AppBinding binding) {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    binding.addPostFrameCallback(() {
      _notifyScheduled = false;
      web.document.dispatchEvent(web.CustomEvent(liveEvent));
      if (!_started) {
        _started = true;
        try {
          if (_states.isNotEmpty) _startTools(_states.last.component);
        } on Object catch (error) {
          // The tool must never break the app it describes.
          web.console.warn('[jaspr_anatomy] Could not start: $error'.toJS);
        }
      }
    });
  }

  static JSObject? _collect() {
    for (final state in _states.reversed) {
      if (!state.mounted) continue;
      final live = collectLive(state.context as Element);
      return JSObject()
        ..['json'] = live.snapshot.encode().toJS
        ..['nodes'] = [for (final node in live.nodes) node].toJS;
    }
    return null;
  }

  /// Adds the overlay or the hotkey listener when no server did.
  static void _startTools(Anatomy anatomy) {
    final document = web.document;
    final serverManaged =
        document.getElementById(anatomyDataId) != null ||
        document.getElementById(anatomyOverlayId) != null ||
        document.getElementById(anatomyHotkeyId) != null ||
        globalContext.has('__jasprAnatomy');
    if (serverManaged) return;

    final mode = AnatomyMode.forRequest(
      // Dart's Uri parser fails on some URLs in development builds (DDC), so
      // the browser parses the query.
      query: _query(),
      cookie: readCookie(web.document.cookie, anatomyCookie),
      hotkey: anatomy.hotkey,
    );
    switch (mode) {
      case AnatomyMode.full || AnatomyMode.data:
        // kReleaseMode is a compile-time constant, so release builds of the
        // client drop the overlay program (about 230 KB) entirely. Server
        // mode does not need it here: the server inlines the overlay.
        if (kReleaseMode) {
          web.console.info('[jaspr_anatomy] The overlay is not part of release builds of the client.'.toJS);
        } else {
          _addScript(anatomyOverlayId, overlayBundle, editorUrl: anatomy.editorUrl);
        }
      case AnatomyMode.hotkey:
        _addScript(anatomyHotkeyId, hotkeyScript);
      case AnatomyMode.off:
        break;
    }
  }

  static void _addScript(String id, String source, {String? editorUrl}) {
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..id = id
      ..text = source;
    if (editorUrl != null) script.setAttribute('data-editor', editorUrl);
    // In <head>, so the app's own part of the page stays as it was.
    (web.document.head ?? web.document.documentElement!).appendChild(script);
  }

  static Map<String, String> _query() {
    final result = <String, String>{};
    final params = web.URLSearchParams(web.window.location.search.toJS);
    (params as JSObject).callMethod<JSAny?>(
      'forEach'.toJS,
      ((JSString value, JSString key) {
        result[key.toDart] = value.toDart;
      }).toJS,
    );
    return result;
  }
}
