import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'card.dart';

/// Rendered on the server after an asynchronous load.
class LatestNews extends AsyncStatelessComponent {
  const LatestNews({super.key});

  @override
  Future<Component> build(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return section(classes: 'news', [
      h2([Component.text('Latest')]),
      ul(classes: 'news-list', [
        for (final (title, tag) in const [
          ('Overlay ships', 'New'),
          ('Reports for agents', 'New'),
          ('Flutter next', 'Soon'),
        ])
          li(classes: 'news-item', [Component.text(title), Badge(tag)]),
      ]),
    ]);
  }
}
