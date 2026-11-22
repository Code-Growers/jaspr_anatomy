import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A client component: rendered on the server, then made interactive in the browser.
@client
class ThemeToggle extends StatefulComponent {
  const ThemeToggle({super.key});

  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle> {
  bool dark = false;

  @override
  Component build(BuildContext context) {
    return button(
      classes: dark ? 'theme-toggle dark' : 'theme-toggle',
      onClick: () => setState(() => dark = !dark),
      [Component.text(dark ? 'Dark' : 'Light')],
    );
  }
}
