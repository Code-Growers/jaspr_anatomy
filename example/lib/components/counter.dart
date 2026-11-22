import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'button.dart';

/// A client component that contains another component.
@client
class Counter extends StatefulComponent {
  const Counter({this.label = 'Seats', super.key});

  final String label;

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 1;

  @override
  Component build(BuildContext context) {
    return div(classes: 'counter', [
      span(classes: 'counter-label', [Component.text('${component.label}: $count')]),
      Button(label: '+', onPressed: () => setState(() => count++)),
      Button(label: '−', onPressed: () => setState(() => count = count > 1 ? count - 1 : 1)),
    ]);
  }
}
