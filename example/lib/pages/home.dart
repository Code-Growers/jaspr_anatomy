import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/button.dart';
import '../components/card.dart';
import '../components/counter.dart';
import '../components/news.dart';

class HomePage extends StatelessComponent {
  const HomePage({super.key});

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      section(classes: 'hero', [
        h1([Component.text('See what a page is made of')]),
        p(classes: 'lead', [Component.text('Every box on this page is a component, or should be.')]),
        div(classes: 'hero-actions', [
          const Button(label: 'Get started'),
          // Written by hand instead of using Button.
          button(classes: 'btn btn-primary', [Component.text('Read the docs')]),
        ]),
      ]),
      section(classes: 'grid', [
        const Card(title: 'Overlay', children: [Text('Outlines every component on the page.'), Badge('2D')]),
        const Card(title: 'Layers', children: [Text('Stacks them by nesting.'), Badge('3D')]),
        const Card(title: 'Seats', children: [Counter()]),
        // A copy of what Card renders, written inline.
        div(classes: 'card', [
          h3(classes: 'card-title', [Component.text('Reports')]),
          div(classes: 'card-body', [Component.text('The same tree as text, for coding agents.')]),
        ]),
      ]),
      const InfoBox(title: 'Tip', text: 'Press Alt+Shift+A to turn the overlay on.'),
      const LatestNews(),
    ]);
  }
}

/// A text node as a component, so the page also has a component without a box.
class Text extends StatelessComponent {
  const Text(this.value, {super.key});

  final String value;

  @override
  Component build(BuildContext context) => Component.text(value);
}
