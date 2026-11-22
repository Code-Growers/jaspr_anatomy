/// Server entrypoint of the example site.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_anatomy/jaspr_anatomy.dart';

import 'app.dart';
import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      title: 'Anatomy example',
      head: [link(rel: 'stylesheet', href: 'styles.css')],
      // The one line that makes the page inspectable. It does nothing in
      // release builds, and nothing for requests that do not ask for it.
      body: const Anatomy(child: App()),
    ),
  );
}
