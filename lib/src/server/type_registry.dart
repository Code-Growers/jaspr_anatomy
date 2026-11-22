import 'dart:isolate';

import '../core/snapshot.dart';
import 'source_locator_stub.dart' if (dart.library.mirrors) 'source_locator_mirrors.dart';

/// Component classes that belong to Jaspr itself, used when the runtime cannot
/// tell us which library a class comes from.
const Set<String> _frameworkNames = {
  'Builder',
  'StatefulBuilder',
  'ListenableBuilder',
  'ValueListenableBuilder',
  'AsyncBuilder',
  'AsyncStatelessComponent',
  'FutureBuilder',
  'StreamBuilder',
  'Document',
  'Head',
  'Style',
  'RawText',
  'ClientApp',
  'SlottedChildView',
  'InheritedComponent',
  'ObserverComponent',
  'Anatomy',
};

/// Collects the [ComponentType]s seen during one render and classifies them.
class TypeRegistry {
  final List<ComponentType> types = [];
  final Map<Type, int> _indexByType = {};
  final Map<String, int> _indexById = {};
  final Map<String, String?> _fileByLibrary = {};

  /// Whether libraries and lines are available on this runtime.
  bool get hasLocations => canLocateTypes;

  /// Returns the index of [type] in [types], adding it on first sight.
  int indexOf(Type type) => _indexByType[type] ??= _register(type);

  /// The registered type for [type].
  ComponentType lookup(Type type) => types[indexOf(type)];

  int _register(Type type) {
    final location = locateType(type);
    final library = location.library;
    final info = ComponentType(name: location.name, library: library, line: location.line);
    // Generic instantiations such as Card<int> and Card<String> share a declaration.
    final existing = _indexById[info.id];
    if (existing != null) return existing;

    if (library == null) {
      info.origin = _frameworkNames.contains(info.name) || isHtmlHelperName(info.name)
          ? Origin.framework
          : Origin.unknown;
    } else {
      final uri = Uri.parse(library);
      info
        ..package = uri.isScheme('package') ? uri.pathSegments.first : null
        ..file = _fileFor(uri);
      info.origin = _classify(uri, info.file);
    }
    types.add(info);
    return _indexById[info.id] = types.length - 1;
  }

  Origin _classify(Uri library, String? file) {
    if (library.isScheme('dart')) return Origin.framework;
    if (library.isScheme('package')) {
      final package = library.pathSegments.first;
      if (package == 'jaspr' || package == 'jaspr_anatomy') return Origin.framework;
      // Hosted and git dependencies live in the pub cache; everything else is
      // source the developer can edit.
      if (file == null || file.contains('/.pub-cache/') || file.contains(r'\Pub\Cache\')) return Origin.package;
    }
    return Origin.project;
  }

  String? _fileFor(Uri library) => _fileByLibrary[library.toString()] ??= _resolveFile(library);

  static String? _resolveFile(Uri library) {
    try {
      if (library.isScheme('file')) return library.toFilePath();
      if (library.isScheme('package')) {
        final resolved = Isolate.resolvePackageUriSync(library);
        if (resolved != null && resolved.isScheme('file')) return resolved.toFilePath();
      }
    } on Object {
      // Not resolvable on this runtime.
    }
    return null;
  }
}

/// Whether [library] is where Jaspr declares its HTML helper components
/// (`div`, `span`, …).
bool isHtmlHelperLibrary(String library) => library.startsWith('package:jaspr/src/dom/html/');

/// Jaspr's HTML helpers are the only components whose class names start with a
/// lower-case letter. Used when the library is unknown.
bool isHtmlHelperName(String name) {
  if (name.isEmpty) return false;
  final first = name.codeUnitAt(0);
  return first >= 0x61 && first <= 0x7a;
}
