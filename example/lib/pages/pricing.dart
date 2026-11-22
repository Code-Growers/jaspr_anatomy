import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/button.dart';
import '../components/card.dart';
import '../components/counter.dart';

class PricingPage extends StatelessComponent {
  const PricingPage({super.key});

  /// Three tiers written inline: the same structure three times.
  Component _tier(String name, String price, List<String> features, {bool popular = false}) {
    return div(classes: 'tier', [
      h3(classes: 'tier-name', [Component.text(name), if (popular) const Badge('Popular')]),
      p(classes: 'tier-price', [Component.text(price)]),
      ul(classes: 'tier-features', [
        for (final feature in features) li([Component.text(feature)]),
      ]),
      Button(label: 'Choose $name'),
    ]);
  }

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      h1([Component.text('Pricing')]),
      section(classes: 'tiers', [
        _tier('Solo', '0 €', ['One project', 'Overlay']),
        _tier('Team', '29 €', ['Ten projects', 'Overlay', 'Reports'], popular: true),
        _tier('Company', '99 €', ['Unlimited projects', 'Overlay', 'Reports', 'Support']),
      ]),
      const Counter(label: 'Team size'),
      // No <tbody>: the browser adds one, so the page differs from what was written.
      table(classes: 'compare', [
        tr([
          th([Component.text('Feature')]),
          th([Component.text('Solo')]),
          th([Component.text('Team')]),
        ]),
        tr([
          td([Component.text('Overlay')]),
          td([Component.text('Yes')]),
          td([Component.text('Yes')]),
        ]),
        tr([
          td([Component.text('Reports')]),
          td([Component.text('No')]),
          td([Component.text('Yes')]),
        ]),
      ]),
      const Callout(title: 'Note', text: 'Prices are made up.'),
    ]);
  }
}
