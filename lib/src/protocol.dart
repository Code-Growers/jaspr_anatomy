/// Names shared by the server, the overlay and the command-line tools.
///
/// Pure Dart: imported on the server, in the browser and in the CLI.
library;

/// Request header that asks the server for anatomy data.
///
/// The value `data` returns only the JSON; any other value also returns the overlay.
const String anatomyHeader = 'x-jaspr-anatomy';

/// Cookie the overlay sets so that anatomy data stays on across navigations.
const String anatomyCookie = 'jaspr_anatomy';

/// Query parameter that turns anatomy on (`?anatomy`) or off (`?anatomy=0`) for one request.
const String anatomyQuery = 'anatomy';

/// `id` of the `<script type="application/json">` element holding the snapshot.
const String anatomyDataId = '__jaspr_anatomy__';

/// `id` of the `<script>` element holding the overlay program.
const String anatomyOverlayId = '__jaspr_anatomy_overlay__';

/// `id` of the `<script>` element holding the hotkey listener.
const String anatomyHotkeyId = '__jaspr_anatomy_hotkey__';

/// Global the app's client program sets when it runs inside an [Anatomy]:
/// an object whose `collect()` describes the live component tree.
///
/// Value: `{version: int, collect: () => {json: String, nodes: Node?[]}}`. The
/// JSON is an `AnatomySnapshot`; `nodes[i]` is the DOM node of the node whose
/// depth-first index is `i`.
const String liveApiName = '__jasprAnatomyLive';

/// Version of the [liveApiName] object.
const int liveApiVersion = 1;

/// Event the client program dispatches on `document` when the live tree is
/// ready or has been rebuilt.
const String liveEvent = 'jaspr-anatomy-live';

/// Prefix dart2js puts before a minified class name in `Type.toString()`.
const String minifiedPrefix = 'minified:';

/// Whether [name] is a class name that a minifying compiler shortened.
bool isMinifiedName(String name) => name.startsWith(minifiedPrefix);

/// Component classes that belong to Jaspr itself, used when the runtime cannot
/// tell which library a class comes from.
const Set<String> frameworkComponentNames = {
  'Builder',
  'StatefulBuilder',
  'ListenableBuilder',
  'ValueListenableBuilder',
  'AsyncBuilder',
  'AsyncStatelessComponent',
  'FutureBuilder',
  'StreamBuilder',
  'Document',
  'Head',
  'Style',
  'RawText',
  'ClientApp',
  'ChildSlot',
  'SlottedChildView',
  'InheritedComponent',
  'ObserverComponent',
  'Anatomy',
};

/// Jaspr's HTML helpers are the only components whose class names start with a
/// lower-case letter. Used when the library is unknown.
bool isHtmlHelperName(String name) {
  if (name.isEmpty || isMinifiedName(name)) return false;
  final first = name.codeUnitAt(0);
  return first >= 0x61 && first <= 0x7a;
}

/// The value of cookie [name] in a `Cookie` request header (or in
/// `document.cookie`), or null. Tolerates empty and malformed parts, which
/// stricter parsers reject.
String? readCookie(String? header, String name) {
  if (header == null) return null;
  for (final part in header.split(';')) {
    final index = part.indexOf('=');
    if (index < 0) continue;
    if (part.substring(0, index).trim() == name) return part.substring(index + 1).trim();
  }
  return null;
}

/// Link template for opening a source file from the overlay: VS Code.
const String defaultEditorUrl = 'vscode://file/{file}:{line}';

/// What the server adds to a response.
enum AnatomyMode {
  /// Nothing.
  off,

  /// Only the hotkey listener.
  hotkey,

  /// The snapshot JSON, for tools.
  data,

  /// The snapshot JSON and the overlay, for people.
  full;

  /// Whether the snapshot JSON is part of the response.
  bool get hasData => this == data || this == full;

  /// Decides what a request gets. An explicit [header] wins over the query
  /// parameter in [url] (or [query], when the caller parsed it already),
  /// which wins over the [cookie].
  static AnatomyMode forRequest({
    String? url,
    Map<String, String>? query,
    String? header,
    String? cookie,
    required bool hotkey,
  }) {
    final fallback = hotkey ? AnatomyMode.hotkey : AnatomyMode.off;
    if (header != null) return _parse(header) ?? fallback;
    query ??= url == null ? null : Uri.tryParse(url)?.queryParameters;
    if (query != null && query.containsKey(anatomyQuery)) return _parse(query[anatomyQuery]!) ?? fallback;
    if (cookie == '1') return AnatomyMode.full;
    return fallback;
  }

  /// Returns null when [value] asks for anatomy to be off.
  static AnatomyMode? _parse(String value) => switch (value.trim().toLowerCase()) {
    '0' || 'off' || 'false' => null,
    'data' || 'json' => AnatomyMode.data,
    _ => AnatomyMode.full,
  };
}

/// The script added to pages that did not ask for anatomy data: Alt+Shift+A
/// sets the cookie and reloads. `?anatomy=0` clears the cookie; the hotkey
/// drops that parameter when it reloads, since it would win over the cookie.
const String hotkeyScript =
    "(function(){var d=document,c='$anatomyCookie';"
    r"if(/[?&]anatomy=(0|off|false)(&|$)/.test(location.search)){d.cookie=c+'=;path=/;max-age=0'}"
    "d.addEventListener('keydown',function(e){if(e.altKey&&e.shiftKey&&e.code==='KeyA'){"
    "e.preventDefault();d.cookie=c+'=1;path=/;SameSite=Lax';"
    "var u=new URL(location.href);if(u.searchParams.has('anatomy')){u.searchParams.delete('anatomy');"
    "location.href=u.href}else{location.reload()}}})})();";
