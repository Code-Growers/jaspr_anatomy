import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'theme_toggle.dart';

class SiteHeader extends StatelessComponent {
  const SiteHeader({required this.current, super.key});

  final String current;

  @override
  Component build(BuildContext context) {
    return header(classes: 'site-header', [
      const Logo(),
      nav(classes: 'site-nav', [
        NavLink(href: '/', label: 'Home', active: current == '/'),
        NavLink(href: '/pricing', label: 'Pricing', active: current == '/pricing'),
        NavLink(href: '/team', label: 'Team', active: current == '/team'),
      ]),
      const ThemeToggle(),
    ]);
  }
}

/// Raw HTML: the tool cannot see inside it and says so.
class Logo extends StatelessComponent {
  const Logo({super.key});

  @override
  Component build(BuildContext context) {
    return a(href: '/', classes: 'logo', [
      RawText(
        '<svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">'
        '<circle cx="12" cy="12" r="10" fill="currentColor"></circle></svg>',
      ),
      span([Component.text('Anatomy')]),
    ]);
  }
}

class NavLink extends StatelessComponent {
  const NavLink({required this.href, required this.label, this.active = false, super.key});

  final String href;
  final String label;
  final bool active;

  @override
  Component build(BuildContext context) {
    return a(href: href, classes: active ? 'nav-link active' : 'nav-link', [Component.text(label)]);
  }
}

class SiteFooter extends StatelessComponent {
  const SiteFooter({super.key});

  @override
  Component build(BuildContext context) {
    return footer(classes: 'site-footer', [
      p([Component.text('An example site for jaspr_anatomy.')]),
      nav(classes: 'site-nav', [
        const NavLink(href: '/', label: 'Home'),
        const NavLink(href: '/pricing', label: 'Pricing'),
        const NavLink(href: '/team', label: 'Team'),
      ]),
    ]);
  }
}
