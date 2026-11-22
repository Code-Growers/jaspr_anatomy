/// See which Jaspr components make up a rendered page.
///
/// Wrap the page body in [Anatomy] on the server, and the root passed to
/// `runApp` in the browser. See the README for how to turn the overlay on and
/// how to read a page's structure from the command line.
library;

export 'src/anatomy_passthrough.dart'
    if (dart.library.io) 'src/server/anatomy_server.dart'
    if (dart.library.js_interop) 'src/client/anatomy_client.dart'
    show Anatomy;
