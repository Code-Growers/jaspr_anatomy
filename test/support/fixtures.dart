import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

/// A page with shared components, repeated markup, a client component and
/// the output shapes that are easy to get wrong.
class FixturePage extends StatelessComponent {
  const FixturePage({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      const SiteHeader(),
      main_([
        section(classes: 'cards', [
          const Card(
            title: 'One',
            child: Button(label: 'Open'),
          ),
          const Card(
            title: 'Two',
            child: Button(label: 'Open'),
          ),
          const Card(title: 'Three', child: Counter()),
        ]),
        // Inline markup that repeats what Card renders, without using it.
        div(classes: 'card', [
          h3(classes: 'card-title', [Component.text('Inline')]),
          div(classes: 'card-body', [Component.text('Not a component')]),
        ]),
        const TextOnly(),
        const Pair(),
      ]),
    ]);
  }
}

class SiteHeader extends StatelessComponent {
  const SiteHeader({super.key});

  @override
  Component build(BuildContext context) {
    return header(classes: 'site-header', [
      nav([
        const NavLink(href: '/', label: 'Home'),
        const NavLink(href: '/about', label: 'About'),
        const NavLink(href: '/pricing', label: 'Pricing'),
      ]),
    ]);
  }
}

class NavLink extends StatelessComponent {
  const NavLink({required this.href, required this.label, super.key});

  final String href;
  final String label;

  @override
  Component build(BuildContext context) => a(href: href, classes: 'nav-link', [Component.text(label)]);
}

class Card extends StatelessComponent {
  const Card({required this.title, required this.child, super.key});

  final String title;
  final Component child;

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      h3(classes: 'card-title', [Component.text(title)]),
      div(classes: 'card-body', [child]),
    ]);
  }
}

/// A wrapper that renders exactly what [BaseButton] renders.
class Button extends StatelessComponent {
  const Button({required this.label, super.key});

  final String label;

  @override
  Component build(BuildContext context) => BaseButton(label: label);
}

class BaseButton extends StatelessComponent {
  const BaseButton({required this.label, super.key});

  final String label;

  @override
  Component build(BuildContext context) => button(classes: 'btn btn-primary', [Component.text(label)]);
}

/// Registered as a client component in the test's [ServerOptions].
class Counter extends StatelessComponent {
  const Counter({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'counter', [
      const BaseButton(label: '+'),
      span([Component.text('0')]),
    ]);
  }
}

/// A component whose whole output is a text node.
class TextOnly extends StatelessComponent {
  const TextOnly({super.key});

  @override
  Component build(BuildContext context) => Component.text('Just text');
}

/// A component whose output is two sibling elements.
class Pair extends StatelessComponent {
  const Pair({super.key});

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      p(classes: 'first', [Component.text('First')]),
      p(classes: 'second', [Component.text('Second')]),
    ]);
  }
}

/// Resolves after a delay, so its children mount after later siblings.
class SlowSection extends AsyncStatelessComponent {
  const SlowSection({super.key});

  @override
  Future<Component> build(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return section(classes: 'slow', [const Button(label: 'Late')]);
  }
}

class Throwing extends StatelessComponent {
  const Throwing({super.key});

  @override
  Component build(BuildContext context) => throw StateError('boom');
}

class AsyncThrowing extends AsyncStatelessComponent {
  const AsyncThrowing({super.key});

  @override
  Future<Component> build(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    throw StateError('async boom');
  }
}

/// Components whose output sits inside elements with raw text content.
class RawTextParents extends StatelessComponent {
  const RawTextParents({super.key});

  @override
  Component build(BuildContext context) {
    return div([
      textarea([const TextOnly()]),
      script(content: 'window.x = 1 < 2;'),
      Component.element(tag: 'style', children: [RawText('.a > .b { color: red }')]),
      RawText('<svg class="icon"><path d="M0 0"></path></svg>'),
      const Button(label: 'After'),
    ]);
  }
}

/// Adds to the document head from inside the body.
class WithHead extends StatelessComponent {
  const WithHead({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'with-head', [
      Document.head(
        title: 'Fixture',
        children: [meta(name: 'fixture', content: 'yes')],
      ),
      const Button(label: 'Body'),
    ]);
  }
}

/// Text that would end a script element if it were not escaped.
class Hostile extends StatelessComponent {
  const Hostile({super.key});

  @override
  Component build(BuildContext context) => p([Component.text('</script><script>alert(1)</script>')]);
}
