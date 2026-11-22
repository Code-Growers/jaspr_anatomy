# jaspr_anatomy

Generic MIT-licensed Dart package. Keep application code and assets out of this repository.

## Layout

- `lib/src/core/`: snapshot schema, reuse analysis, report rendering. Pure Dart. No `package:jaspr`, `package:web`, `dart:io` or Flutter imports: it is shared by the server, the overlay and the command-line tools, and is meant to be lifted out for a Flutter collector.
- `lib/src/server/`: the `Anatomy` component and the collector. Uses Jaspr's render-adapter API.
- `lib/src/overlay/`: the browser program. Imports `package:web`; never imported by server code.
- `lib/src/server/overlay_bundle.g.dart`: generated from the overlay. Do not edit.
- `lib/inspect.dart`, `lib/scan.dart`, `bin/`: VM-only command-line tools.
- `example/`: a site with deliberate reuse problems. Tests scan it.

## Rules

- The app's own markup must stay untouched. `test/server` asserts that a page with anatomy on is byte-identical to the plain page apart from the appended scripts. Keep that test strict.
- After changing `lib/src/overlay/`, `lib/src/core/` or `lib/src/protocol.dart`, run `dart run tool/build_overlay.dart` and commit the bundle.
- Do not write a backslash followed by `u` and four hex digits in Dart source for the JSON escape of `<`; see `_escapedLessThan` in `anatomy_server.dart` for why and how.

## Before finishing

```sh
dart format .
dart analyze --fatal-infos
dart run tool/build_overlay.dart --check
dart test
dart test -p chrome test/overlay
```

Verify overlay changes in a browser against `example/` (`jaspr serve`, then open a page with `?anatomy`).
