/// Fallback for runtimes without `dart:mirrors` (ahead-of-time compiled servers).
library;

/// Where a class is declared.
typedef TypeLocation = ({String name, String? library, int? line});

/// Whether [locateType] can report libraries and lines on this runtime.
const bool canLocateTypes = false;

/// Returns the name of [type]; the library and line are unknown here.
TypeLocation locateType(Type type) => (name: stripTypeArguments(type.toString()), library: null, line: null);

/// `Card<int>` becomes `Card`.
String stripTypeArguments(String name) {
  final index = name.indexOf('<');
  return index < 0 ? name : name.substring(0, index);
}
