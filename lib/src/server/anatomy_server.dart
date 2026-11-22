import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';

import '../core/snapshot.dart';
import '../protocol.dart';
import 'collector.dart';
import 'overlay_bundle.g.dart';

/// Makes the component structure of the page below it inspectable.
///
/// Place it inside the document body, around the app:
///
/// ```dart
/// Document(body: Anatomy(child: App()))
/// ```
///
/// Nothing is added to a page unless [enabled] is true **and** the request asks
/// for it with the `jaspr_anatomy` cookie, an `?anatomy` query parameter or an
/// `X-Jaspr-Anatomy` header. Requests that do not ask get the normal page, plus
/// a few bytes of script that listen for the Alt+Shift+A hotkey when [hotkey]
/// is true.
class Anatomy extends StatelessComponent {
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
  /// false for release builds and ahead-of-time compiled servers.
  final bool enabled;

  /// Whether pages that did not ask for anatomy data still get the small
  /// script that turns it on with Alt+Shift+A.
  final bool hotkey;

  /// Link template the overlay uses to open a source file, with `{file}` and
  /// `{line}`. Defaults to VS Code; for IntelliJ and Android Studio use
  /// `idea://open?file={file}&line={line}`.
  final String editorUrl;

  @override
  Component build(BuildContext context) {
    if (enabled) {
      final binding = context.binding;
      if (binding is ServerAppBinding) {
        final mode = AnatomyMode.forRequest(
          url: binding.currentUrl,
          header: binding.request.headers.singleValues[anatomyHeader],
          // Not binding.cookies: it throws on a malformed Cookie header, and
          // the tool must never break a page.
          cookie: readCookie(binding.request.headers.singleValues['cookie'], anatomyCookie),
          hotkey: hotkey,
        );
        if (mode != AnatomyMode.off) {
          binding.addRenderAdapter(_AnatomyAdapter(context as Element, mode, editorUrl));
        }
      }
    }
    return child;
  }
}

/// Appends the anatomy scripts after the output of the [Anatomy] element.
final class _AnatomyAdapter extends ElementBoundaryAdapter {
  // Above the priority of a @client component boundary, so the scripts land
  // outside the markers of an island that is the direct child.
  _AnatomyAdapter(super.element, this.mode, this.editorUrl) : super(priority: 1500);

  final AnatomyMode mode;
  final String editorUrl;

  bool _hasOutput = false;
  String? _snapshotJson;

  static bool _warnedAboutPlacement = false;
  static bool _warnedAboutBundle = false;

  @override
  FutureOr<void> prepare() {
    // A component whose build failed has no output to wrap.
    if (element.slot.target == null) return null;
    _hasOutput = true;
    return super.prepare();
  }

  @override
  void apply(MarkupRenderObject root) {
    if (_hasOutput) super.apply(root);
  }

  @override
  void prepareBoundary(ChildGroup group) {
    if (!mode.hasData) return;
    final snapshot = collectSnapshot(element, binding);
    if (snapshot.roots.isEmpty && !_warnedAboutPlacement) {
      _warnedAboutPlacement = true;
      stderr.writeln(
        '[jaspr_anatomy] Nothing to describe. Place Anatomy inside the document body, '
        'for example Document(body: Anatomy(child: App())).',
      );
    }
    _snapshotJson = encodeForScript(snapshot);
  }

  @override
  void applyBoundary(ChildGroup group) {
    final html = StringBuffer();
    if (_snapshotJson case final json?) {
      const escape = HtmlEscape(HtmlEscapeMode.attribute);
      html.write(
        '<script type="application/json" id="$anatomyDataId" '
        'data-root="${escape.convert(Directory.current.path)}" '
        'data-editor="${escape.convert(editorUrl)}">$json</script>',
      );
    }
    switch (mode) {
      case AnatomyMode.full:
        if (overlayBundle.isEmpty) {
          if (!_warnedAboutBundle) {
            _warnedAboutBundle = true;
            stderr.writeln('[jaspr_anatomy] The overlay bundle is missing. Run: dart run tool/build_overlay.dart');
          }
        } else {
          html.write('<script id="$anatomyOverlayId">$overlayBundle</script>');
        }
      case AnatomyMode.hotkey:
        html.write('<script id="$anatomyHotkeyId">$hotkeyScript</script>');
      case AnatomyMode.data || AnatomyMode.off:
        break;
    }
    if (html.isNotEmpty) {
      group.children.insertBefore(MarkupRenderText(html.toString(), true));
    }
  }
}

/// Encodes [snapshot] so it can sit inside a `<script>` element: no `<`, so the
/// HTML parser cannot be led out of the element.
String encodeForScript(AnatomySnapshot snapshot) => snapshot.encode().replaceAll('<', _escapedLessThan);

/// The JSON escape for `<`: a backslash, `u`, and the code point 003c.
/// Assembled from two literals so the six characters stay visible as such.
const String _escapedLessThan =
    r'\'
    'u003c';
