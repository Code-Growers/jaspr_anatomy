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
  /// parameter in [url], which wins over the [cookie].
  static AnatomyMode forRequest({required String url, String? header, String? cookie, required bool hotkey}) {
    final fallback = hotkey ? AnatomyMode.hotkey : AnatomyMode.off;
    if (header != null) return _parse(header) ?? fallback;
    final query = Uri.tryParse(url)?.queryParameters;
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
/// sets the cookie and reloads. `?anatomy=0` clears the cookie.
const String hotkeyScript =
    "(function(){var d=document,c='$anatomyCookie';"
    r"if(/[?&]anatomy=(0|off|false)(&|$)/.test(location.search)){d.cookie=c+'=;path=/;max-age=0'}"
    "d.addEventListener('keydown',function(e){if(e.altKey&&e.shiftKey&&e.code==='KeyA'){"
    "e.preventDefault();d.cookie=c+'=1;path=/;SameSite=Lax';location.reload()}})})();";
