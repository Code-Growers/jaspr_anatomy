import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'components/layout.dart';
import 'pages/home.dart';
import 'pages/pricing.dart';
import 'pages/team.dart';

/// Picks the page for the requested path and puts it in the shared layout.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    final path = Uri.parse(context.url).path;
    return div(classes: 'app', [
      SiteHeader(current: path),
      main_(classes: 'content', [
        switch (path) {
          '/pricing' => const PricingPage(),
          '/team' => const TeamPage(),
          _ => const HomePage(),
        },
      ]),
      const SiteFooter(),
    ]);
  }
}
