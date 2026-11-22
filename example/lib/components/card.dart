import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class Card extends StatelessComponent {
  const Card({required this.title, required this.children, super.key});

  final String title;
  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      h3(classes: 'card-title', [Component.text(title)]),
      div(classes: 'card-body', children),
    ]);
  }
}

class Badge extends StatelessComponent {
  const Badge(this.label, {super.key});

  final String label;

  @override
  Component build(BuildContext context) => span(classes: 'badge', [Component.text(label)]);
}

/// Two components that render the same structure: candidates for merging.
class InfoBox extends StatelessComponent {
  const InfoBox({required this.title, required this.text, super.key});

  final String title;
  final String text;

  @override
  Component build(BuildContext context) {
    return aside(classes: 'notice', [
      strong(classes: 'notice-title', [Component.text(title)]),
      p(classes: 'notice-text', [Component.text(text)]),
    ]);
  }
}

class Callout extends StatelessComponent {
  const Callout({required this.title, required this.text, super.key});

  final String title;
  final String text;

  @override
  Component build(BuildContext context) {
    return aside(classes: 'notice', [
      strong(classes: 'notice-title', [Component.text(title)]),
      p(classes: 'notice-text', [Component.text(text)]),
    ]);
  }
}
