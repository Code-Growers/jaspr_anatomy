/// Client entrypoint of the example site.
library;

import 'package:jaspr/client.dart';
import 'package:jaspr_anatomy/jaspr_anatomy.dart';

import 'main.client.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);
  // Lets the overlay follow what client components build after load.
  runApp(const Anatomy(child: ClientApp()));
}
