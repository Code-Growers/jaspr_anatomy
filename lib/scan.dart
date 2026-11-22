/// Finds component classes and where they are constructed, by reading source.
///
/// VM only: uses the Dart analyzer and `dart:io`. Never import this from code
/// that runs in a browser.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when a project cannot be scanned.
class ScanException implements Exception {
  ScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One place where a component is constructed.
class ComponentUse {
  ComponentUse({required this.file, required this.line, required this.package, this.within});

  /// Absolute path of the file.
  final String file;
  final int line;

  /// Package the file belongs to.
  final String package;

  /// The class or function the construction is written in.
  final String? within;

  Map<String, Object?> toJson(String root) => {
    'file': p.relative(file, from: root),
    'line': line,
    'package': package,
    'within': ?within,
  };
}

/// A component class found in source.
class ScannedComponent {
  ScannedComponent({
    required this.name,
    required this.library,
    required this.package,
    required this.file,
    required this.line,
    required this.kind,
    required this.isAbstract,
    required this.isClient,
  });

  final String name;

  /// Library URI, such as `package:app/components/card.dart`.
  final String library;
  final String package;

  /// Absolute path of the declaring file.
  final String file;
  final int line;

  /// `stateless`, `stateful`, `inherited`, `async` or `other`.
  final String kind;
  final bool isAbstract;

  /// Whether the class is annotated with `@client`.
  final bool isClient;

  final List<ComponentUse> uses = [];

  /// Matches `ComponentType.id` in snapshots.
  String get id => '$library#$name';

  bool get isPrivate => name.startsWith('_');

  /// Number of distinct files that construct this component.
  int get usingFiles => {for (final use in uses) use.file}.length;

  Set<String> get usingPackages => {for (final use in uses) use.package};

  Map<String, Object?> toJson(String root) => {
    'name': name,
    'library': library,
    'package': package,
    'file': p.relative(file, from: root),
    'line': line,
    'kind': kind,
    if (isAbstract) 'abstract': true,
    if (isClient) 'client': true,
    'uses': [for (final use in uses) use.toJson(root)],
  };
}

/// What a scan found.
class ScanResult {
  ScanResult({required this.root, required this.package, required this.packages, required this.components});

  /// Absolute path of the scanned app.
  final String root;

  /// Name of the app's package.
  final String package;

  /// Names of the packages that were read: the app and the local packages it depends on.
  final List<String> packages;

  /// Component classes, by name.
  final List<ScannedComponent> components;

  int get uses => components.fold(0, (sum, component) => sum + component.uses.length);

  /// Concrete components that nothing constructs.
  List<ScannedComponent> get unused =>
      components.where((component) => !component.isAbstract && component.uses.isEmpty).toList();

  /// Components constructed in exactly one place.
  List<ScannedComponent> get singleUse => components.where((component) => component.uses.length == 1).toList();

  Map<String, Object?> toJson() => {
    'root': root,
    'package': package,
    'packages': packages,
    'components': [for (final component in components) component.toJson(root)],
  };
}

/// Where `scan` stores its result for other tools, relative to the app root.
const String scanIndexPath = '.dart_tool/jaspr_anatomy/scan.json';

/// Reads the app at [root] and the local packages it depends on.
///
/// Only `lib/` directories are read. Generated files (`*.g.dart`,
/// `*.options.dart`, `*.freezed.dart`) are skipped, so a construction that
/// exists only in generated code does not count as a use.
Future<ScanResult> scanProject(String root) async {
  root = p.normalize(p.absolute(root));
  final pubspecFile = File(p.join(root, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw ScanException('No pubspec.yaml in $root. Run the scan from the root of a Dart package.');
  }
  final appName = _pubspec(pubspecFile)['name'] as String? ?? p.basename(root);

  final local = _localPackages(root);
  if (local == null) {
    throw ScanException('No .dart_tool/package_config.json found for $root. Run "dart pub get" first.');
  }
  local[appName] = root;

  // The app and the local packages reachable from it.
  final included = <String, String>{};
  final queue = [appName];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    final path = local[name];
    // This tool is not part of the app, even when it is used from a local path.
    if (path == null || included.containsKey(name) || name == 'jaspr_anatomy') continue;
    included[name] = path;
    final manifest = File(p.join(path, 'pubspec.yaml'));
    if (!manifest.existsSync()) continue;
    final dependencies = _pubspec(manifest)['dependencies'];
    if (dependencies is Map) queue.addAll(dependencies.keys.cast<String>());
  }

  final libraries = <String, String>{
    for (final entry in included.entries)
      if (Directory(p.join(entry.value, 'lib')).existsSync()) entry.key: p.join(entry.value, 'lib'),
  };
  if (libraries.isEmpty) throw ScanException('Nothing to scan: $root has no lib directory.');

  String packageOf(String file) {
    for (final entry in libraries.entries) {
      if (p.isWithin(entry.value, file)) return entry.key;
    }
    return appName;
  }

  final components = <String, ScannedComponent>{};
  final uses = <String, List<ComponentUse>>{};
  final collection = AnalysisContextCollection(includedPaths: libraries.values.toList());
  try {
    for (final context in collection.contexts) {
      for (final file in context.contextRoot.analyzedFiles()) {
        if (!file.endsWith('.dart') || _isGenerated(file)) continue;
        final result = await context.currentSession.getResolvedUnit(file);
        if (result is! ResolvedUnitResult) continue;
        result.unit.accept(
          _Visitor(
            file: file,
            package: packageOf(file),
            lineInfo: result.lineInfo,
            components: components,
            uses: uses,
          ),
        );
      }
    }
  } finally {
    await collection.dispose();
  }

  for (final component in components.values) {
    component.uses.addAll(uses[component.id] ?? const []);
  }
  final sorted = components.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return ScanResult(root: root, package: appName, packages: libraries.keys.toList(), components: sorted);
}

bool _isGenerated(String file) =>
    file.endsWith('.g.dart') ||
    file.endsWith('.options.dart') ||
    file.endsWith('.freezed.dart') ||
    file.endsWith('.gr.dart');

Map<Object?, Object?> _pubspec(File file) {
  final yaml = loadYaml(file.readAsStringSync());
  return yaml is Map ? yaml : const {};
}

/// Packages whose source is not in the pub cache, by name, or null when no
/// package configuration exists at or above [root].
Map<String, String>? _localPackages(String root) {
  File? config;
  for (var directory = root; ; directory = p.dirname(directory)) {
    final candidate = File(p.join(directory, '.dart_tool', 'package_config.json'));
    if (candidate.existsSync()) {
      config = candidate;
      break;
    }
    if (p.dirname(directory) == directory) break;
  }
  if (config == null) return null;

  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  final base = config.parent.uri;
  final result = <String, String>{};
  for (final entry in (json['packages'] as List<Object?>? ?? const []).cast<Map<String, Object?>>()) {
    final uri = base.resolve(entry['rootUri']! as String);
    if (!uri.isScheme('file')) continue;
    final path = p.normalize(uri.toFilePath());
    // Hosted and git dependencies, and the SDK's own packages, are not the
    // developer's to change.
    final parts = p.split(path);
    if (parts.contains('.pub-cache') || parts.contains('Pub') && parts.contains('Cache')) continue;
    if (parts.contains('flutter') && parts.contains('packages') || parts.contains('dart-sdk')) continue;
    result[entry['name']! as String] = path;
  }
  return result;
}

bool _isJasprComponent(InterfaceElement element) => element.allSupertypes.any(
  (type) => type.element.name == 'Component' && type.element.library.uri.toString().startsWith('package:jaspr/'),
);

String _kindOf(InterfaceElement element) {
  final names = {for (final type in element.allSupertypes) type.element.name};
  if (names.contains('StatefulComponent')) return 'stateful';
  if (names.contains('StatelessComponent')) return 'stateless';
  if (names.contains('InheritedComponent')) return 'inherited';
  if (names.contains('AsyncStatelessComponent')) return 'async';
  return 'other';
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor({
    required this.file,
    required this.package,
    required this.lineInfo,
    required this.components,
    required this.uses,
  });

  final String file;
  final String package;
  final LineInfo lineInfo;
  final Map<String, ScannedComponent> components;
  final Map<String, List<ComponentUse>> uses;

  int _line(int offset) => lineInfo.getLocation(offset).lineNumber;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final fragment = node.declaredFragment;
    final element = fragment?.element;
    final name = element?.name;
    if (element != null && name != null && _isJasprComponent(element)) {
      final component = ScannedComponent(
        name: name,
        library: element.library.uri.toString(),
        package: package,
        file: file,
        line: _line(fragment?.nameOffset ?? node.offset),
        kind: _kindOf(element),
        isAbstract: element.isAbstract,
        isClient: element.metadata.annotations.any((annotation) => annotation.element?.name == 'client'),
      );
      components[component.id] = component;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.element, node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    // A tear-off such as `HomePage.new` also puts the component to use.
    _record(node.constructorName.element, node);
    super.visitConstructorReference(node);
  }

  void _record(ConstructorElement? constructor, AstNode node) {
    final target = constructor?.enclosingElement;
    final name = target?.name;
    if (target == null || name == null) return;
    final library = target.library.uri.toString();
    // Jaspr's own components (every `div(...)` is one) are not the subject.
    if (library.startsWith('package:jaspr/')) return;
    if (!_isJasprComponent(target)) return;
    uses
        .putIfAbsent('$library#$name', () => [])
        .add(ComponentUse(file: file, line: _line(node.offset), package: package, within: _enclosing(node)));
  }

  /// The class or top-level function [node] is written in.
  static String? _enclosing(AstNode node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is ClassDeclaration) return current.declaredFragment?.element.name;
      if (current is MixinDeclaration) return current.declaredFragment?.element.name;
      if (current is ExtensionDeclaration) return current.declaredFragment?.element.name;
      if (current is FunctionDeclaration && current.parent is CompilationUnit) {
        return current.declaredFragment?.element.name;
      }
    }
    return null;
  }
}

// --- Report ------------------------------------------------------------------

String _plural(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : plural ?? '${singular}s'}';

/// A Markdown report of [result]: totals, components nothing constructs,
/// components constructed once, the most used, and how much of each shared
/// package the app uses.
String renderScanReport(ScanResult result, {int limit = 25}) {
  final out = StringBuffer();
  String where(ScannedComponent component) => '${p.relative(component.file, from: result.root)}:${component.line}';
  final concrete = result.components.where((component) => !component.isAbstract).toList();

  out
    ..writeln('# Components in ${result.package}')
    ..writeln()
    ..writeln(
      '${_plural(concrete.length, 'component class', 'component classes')} in '
      '${_plural(result.packages.length, 'package')} (${result.packages.join(', ')}), '
      'constructed in ${_plural(result.uses, 'place')}.',
    );

  final unused = result.unused;
  out
    ..writeln()
    ..writeln('## Never constructed (${unused.length})')
    ..writeln();
  if (unused.isEmpty) {
    out.writeln('None.');
  } else {
    out
      ..writeln('No source file constructs these. Uses in generated code or in tests are not counted.')
      ..writeln();
    for (final component in unused.take(limit)) {
      out.writeln('- `${component.name}`${component.isClient ? ' (client)' : ''} — ${where(component)}');
    }
    if (unused.length > limit) out.writeln('- … ${unused.length - limit} more');
  }

  final single = result.singleUse;
  out
    ..writeln()
    ..writeln('## Constructed in one place (${single.length})')
    ..writeln();
  if (single.isEmpty) {
    out.writeln('None.');
  } else {
    out
      ..writeln('| Component | Source | Constructed in |')
      ..writeln('|---|---|---|');
    for (final component in single.take(limit)) {
      final use = component.uses.single;
      final within = use.within == null ? '' : '`${use.within}` ';
      out.writeln(
        '| ${component.name} | ${where(component)} | $within${p.relative(use.file, from: result.root)}:${use.line} |',
      );
    }
    if (single.length > limit) {
      out
        ..writeln()
        ..writeln('… ${single.length - limit} more.');
    }
  }

  final most = [...concrete]..sort((a, b) => b.uses.length.compareTo(a.uses.length));
  out
    ..writeln()
    ..writeln('## Most used')
    ..writeln()
    ..writeln('| Component | Places | Files | Source |')
    ..writeln('|---|---:|---:|---|');
  for (final component in most.where((component) => component.uses.length > 1).take(limit)) {
    out.writeln('| ${component.name} | ${component.uses.length} | ${component.usingFiles} | ${where(component)} |');
  }

  final shared = result.packages.where((name) => name != result.package).toList();
  if (shared.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Shared packages')
      ..writeln()
      ..writeln('How much of each local package ${result.package} puts to use.')
      ..writeln()
      ..writeln('| Package | Components | Used by ${result.package} | Not used by it |')
      ..writeln('|---|---:|---:|---|');
    for (final name in shared) {
      final own = concrete.where((component) => component.package == name && !component.isPrivate).toList();
      if (own.isEmpty) continue;
      final used = own.where((component) => component.usingPackages.contains(result.package)).toList();
      final idle = own.where((component) => !component.usingPackages.contains(result.package)).toList();
      final sample = idle.take(6).map((component) => component.name).join(', ');
      final more = idle.length > 6 ? ', … ${idle.length - 6} more' : '';
      out.writeln('| $name | ${own.length} | ${used.length} | $sample$more |');
    }
  }
  return out.toString();
}

/// How many places construct each component, keyed like `ComponentType.id` in
/// a snapshot. Reads the file `scan` saved in the app at [root], or returns
/// null when there is none.
Map<String, int>? readCodeUses(String root) {
  final file = File(p.join(root, scanIndexPath));
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return {
      for (final component in (json['components']! as List<Object?>).cast<Map<String, Object?>>())
        '${component['library']}#${component['name']}': (component['uses']! as List<Object?>).length,
    };
  } on Object {
    return null;
  }
}

/// Writes [result] where other tools look for it, and returns the file.
File writeScanIndex(ScanResult result) {
  final file = File(p.join(result.root, scanIndexPath))..parent.createSync(recursive: true);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n');
  return file;
}
