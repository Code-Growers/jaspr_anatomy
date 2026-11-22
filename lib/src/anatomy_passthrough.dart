import 'package:jaspr/jaspr.dart';

import 'protocol.dart';

/// Makes the component structure of the page below it inspectable.
///
/// This is the implementation used outside the server: it renders [child] and
/// nothing else. The server implementation does the work.
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

  /// Whether the tool is available at all.
  final bool enabled;

  /// Whether pages that did not ask for anatomy data still get the hotkey listener.
  final bool hotkey;

  /// Link template the overlay uses to open a source file.
  final String editorUrl;

  @override
  Component build(BuildContext context) => child;
}
