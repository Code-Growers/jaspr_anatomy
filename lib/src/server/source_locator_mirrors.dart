/// Reads class declarations through `dart:mirrors`, which the Dart VM offers
/// when it runs from source (`dart run`, `jaspr serve`).
library;

// The VM still ships dart:mirrors for programs run from source, but marks it
// deprecated. It is an optional enhancer here: source_locator_stub.dart is the
// fallback, and the scan index covers the same ground without it.
// ignore: deprecated_member_use
import 'dart:mirrors';

import 'source_locator_stub.dart' show TypeLocation, stripTypeArguments;

export 'source_locator_stub.dart' show TypeLocation, stripTypeArguments;

/// Whether [locateType] can report libraries and lines on this runtime.
const bool canLocateTypes = true;

/// Returns the name, library URI and declaration line of [type].
TypeLocation locateType(Type type) {
  try {
    final mirror = reflectType(type);
    if (mirror is ClassMirror) {
      final declaration = mirror.originalDeclaration;
      final owner = declaration.owner;
      return (
        name: MirrorSystem.getName(declaration.simpleName),
        library: owner is LibraryMirror ? owner.uri.toString() : null,
        line: declaration.location?.line,
      );
    }
  } on Object {
    // Fall through to the name-only answer.
  }
  return (name: stripTypeArguments(type.toString()), library: null, line: null);
}
