/// Renders snapshots and analyses as text for people and coding agents.
library;

import 'analysis.dart';
import 'snapshot.dart';

/// Options for [renderTree].
class TreeOptions {
  const TreeOptions({this.scope = Scope.project, this.elements = false, this.maxDepth, this.sources = true});

  /// Which components to show. Others are skipped; their children move up.
  final Scope scope;

  /// Whether to show HTML elements between components.
  final bool elements;

  /// Deepest component level to print, or null for all.
  final int? maxDepth;

  /// Whether to print `file:line` next to the first appearance of each class.
  final bool sources;
}

class _Line {
  _Line(this.label, this.children, {this.type});

  final String label;
  final List<_Line> children;
  final ComponentType? type;
  int count = 1;

  /// Identifies lines that would print the same subtree.
  late final String shape = '$label{${children.map((child) => '${child.shape}x${child.count}').join(',')}}';
}

/// An indented tree of the components on a page.
///
/// Identical neighbouring subtrees are merged into one line with a count.
String renderTree(AnatomySnapshot snapshot, {TreeOptions options = const TreeOptions(), String? root}) {
  final seenTypes = <String>{};

  String elementLabel(AnatomyNode node) {
    final id = node.domId == null ? '' : '#${node.domId}';
    final classes = node.classes.take(4).map((name) => '.$name').join();
    return '<${node.tag}$id$classes${node.classes.length > 4 ? '…' : ''}>';
  }

  List<_Line> build(List<AnatomyNode> nodes, int depth) {
    final lines = <_Line>[];
    for (final node in nodes) {
      switch (node.kind) {
        case NodeKind.component:
          final type = snapshot.typeOf(node);
          if (!options.scope.includes(type)) {
            lines.addAll(build(node.children, depth));
            continue;
          }
          final tooDeep = options.maxDepth != null && depth >= options.maxDepth!;
          final marks = [if (node.client != null) 'client', if (node.key != null) 'key ${node.key}'];
          final label = marks.isEmpty ? type.name : '${type.name} (${marks.join(', ')})';
          lines.add(_Line(label, tooDeep ? const [] : build(node.children, depth + 1), type: type));
        case NodeKind.element:
          if (options.elements) {
            lines.add(_Line(elementLabel(node), build(node.children, depth)));
          } else {
            lines.addAll(build(node.children, depth));
          }
        case NodeKind.text || NodeKind.raw:
          break;
      }
    }

    // Merge runs of identical subtrees.
    final merged = <_Line>[];
    for (final line in lines) {
      if (merged.isNotEmpty && merged.last.shape == line.shape) {
        merged.last.count++;
      } else {
        merged.add(line);
      }
    }
    return merged;
  }

  final buffer = StringBuffer();
  void write(List<_Line> lines, String indent) {
    for (final line in lines) {
      buffer.write('$indent${line.label}');
      if (line.count > 1) buffer.write(' ×${line.count}');
      final type = line.type;
      if (options.sources && type != null && seenTypes.add(type.id)) {
        if (shortLocation(type, root: root) case final location?) buffer.write('  — $location');
      }
      buffer.writeln();
      write(line.children, '$indent  ');
    }
  }

  write(build(snapshot.roots, 0), '');
  return buffer.toString();
}

/// `path:line` of [type], relative to [root] when it is inside it.
String? shortLocation(ComponentType type, {String? root}) {
  var file = type.file;
  if (file == null) {
    final library = type.library;
    if (library == null) return null;
    return type.line == null ? library : '$library:${type.line}';
  }
  if (root != null) {
    final prefix = root.endsWith('/') ? root : '$root/';
    if (file.startsWith(prefix)) file = file.substring(prefix.length);
  }
  return type.line == null ? file : '$file:${type.line}';
}

String _percent(double share) => '${(share * 100).round()}%';

String _plural(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : plural ?? '${singular}s'}';

String _owners(Map<String, int> owners) => owners.entries
    .map((entry) {
      final name = entry.key.isEmpty ? 'outside any component' : '`${entry.key}`';
      return entry.value > 1 ? '$name ×${entry.value}' : name;
    })
    .join(', ');

/// One sentence describing [finding].
String describeFinding(MarkupFinding finding) {
  final size = finding.minElements == finding.maxElements
      ? _plural(finding.minElements, 'element')
      : '${finding.minElements}–${finding.maxElements} elements';
  final likeness = finding.identical ? 'identical' : 'same root and children, contents differ';
  final components = finding.components.map((name) => '`$name`').join(', ');
  String onPages(Iterable<Occurrence> occurrences) {
    final pages = {for (final occurrence in occurrences) occurrence.page};
    return pages.length > 1 ? ', on ${pages.length} pages' : '';
  }

  switch (finding.kind) {
    case FindingKind.duplicatesComponent:
      final copies = finding.inline.length;
      return 'Inline markup duplicates $components: ${_plural(copies, 'copy', 'copies')} of '
          '`${finding.shape}` ($size; $likeness) in ${_owners(finding.inlineOwners)}'
          '${onPages(finding.inline)}. Use the component there.';
    case FindingKind.twinComponents:
      return '$components render the same markup `${finding.shape}` ($size; $likeness), '
          '${finding.occurrences.length} times in total${onPages(finding.occurrences)}. Consider merging them.';
    case FindingKind.repeatedInline:
      final owners = finding.inlineOwners;
      final single = owners.length == 1 ? owners.keys.single : null;
      final where = switch (single) {
        null => 'in ${_owners(owners)}',
        '' => 'outside any component',
        _ => 'within `$single`',
      };
      return 'Inline markup `${finding.shape}` ($size; $likeness) repeats '
          '${finding.occurrences.length} times $where${onPages(finding.occurrences)}. '
          'Candidate for a new component.';
  }
}

/// Options for [renderReport].
class ReportOptions {
  const ReportOptions({
    this.tree = true,
    this.treeOptions = const TreeOptions(),
    this.maxFindings = 20,
    this.maxTypes = 60,
    this.root,
    this.codeUses,
  });

  /// Whether to include a component tree per page.
  final bool tree;
  final TreeOptions treeOptions;
  final int maxFindings;
  final int maxTypes;

  /// Directory that file paths are shown relative to.
  final String? root;

  /// From a source scan: in how many places each component is constructed,
  /// by [ComponentType.id]. Adds an "In code" column when given.
  final Map<String, int>? codeUses;
}

/// A Markdown report of [analysis]: totals, component inventory, where inline
/// markup accumulates, repeated markup, and the tree of each page.
String renderReport(Analysis analysis, {ReportOptions options = const ReportOptions()}) {
  final out = StringBuffer();
  final pages = analysis.pages;
  final single = pages.length == 1;

  out.writeln(single ? '# Anatomy of ${pages.single.url}' : '# Anatomy of ${pages.length} pages');
  out.writeln();
  out.writeln(
    '${_plural(analysis.totalElements, 'element')}, '
    '${_plural(analysis.totalInstances, 'component instance')} of '
    '${_plural(analysis.types.length, 'component class', 'component classes')}. '
    '${_percent(analysis.reuseShare)} of the elements come from components used more than once'
    '${single ? ' on this page' : ' across these pages'}.',
  );

  if (!single) {
    out.writeln();
    out.writeln('## Pages');
    out.writeln();
    out.writeln('| Page | Elements | Instances | Classes | From reused components |');
    out.writeln('|---|---:|---:|---:|---:|');
    final ordered = [...pages]..sort((a, b) => a.reuseShare.compareTo(b.reuseShare));
    for (final page in ordered) {
      out.writeln(
        '| ${page.url} | ${page.elements} | ${page.components} | ${page.types} | ${_percent(page.reuseShare)} |',
      );
    }
  }

  out.writeln();
  out.writeln('## Components');
  out.writeln();
  if (analysis.types.isEmpty) {
    out.writeln('No components in scope.');
  } else {
    final codeUses = options.codeUses;
    final header = [
      'Component',
      'Instances',
      if (!single) 'Pages',
      'Own elements',
      if (codeUses != null) 'In code',
      'Inside',
      'Source',
    ];
    final numeric = {'Instances', 'Pages', 'Own elements', 'In code'};
    out.writeln('| ${header.join(' | ')} |');
    out.writeln('|${header.map((name) => numeric.contains(name) ? '---:' : '---').join('|')}|');
    for (final usage in analysis.types.take(options.maxTypes)) {
      final containers = (usage.containers.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(3)
          .map((entry) => entry.key.isEmpty ? '(root)' : entry.key)
          .join(', ');
      final cells = [
        usage.type.name,
        '${usage.instances}',
        if (!single) '${usage.pages}/${pages.length}',
        '${usage.ownElements}',
        if (codeUses != null) '${codeUses[usage.type.id] ?? ''}',
        containers,
        shortLocation(usage.type, root: options.root) ?? '',
      ];
      out.writeln('| ${cells.join(' | ')} |');
    }
    if (analysis.types.length > options.maxTypes) {
      out.writeln();
      out.writeln('… ${analysis.types.length - options.maxTypes} more.');
    }
  }

  final oneOffs = analysis.oneOffs.take(8).toList();
  if (oneOffs.isNotEmpty) {
    out.writeln();
    out.writeln('## Where inline markup accumulates');
    out.writeln();
    out.writeln('Components with a single instance, by how many elements they write themselves.');
    out.writeln();
    for (final usage in oneOffs) {
      final share = analysis.totalElements == 0 ? 0.0 : usage.ownElements / analysis.totalElements;
      final source = shortLocation(usage.type, root: options.root);
      out.writeln(
        '- `${usage.type.name}`: ${_plural(usage.ownElements, 'element')} (${_percent(share)})'
        '${source == null ? '' : ' — $source'}',
      );
    }
  }

  out.writeln();
  out.writeln('## Repeated markup');
  out.writeln();
  if (analysis.findings.isEmpty) {
    out.writeln('Nothing found.');
  } else {
    var index = 1;
    for (final finding in analysis.findings.take(options.maxFindings)) {
      out.writeln('${index++}. ${describeFinding(finding)}');
    }
    if (analysis.findings.length > options.maxFindings) {
      out.writeln();
      out.writeln('… ${analysis.findings.length - options.maxFindings} more.');
    }
  }

  if (options.tree) {
    for (final snapshot in analysis.snapshots) {
      out.writeln();
      out.writeln(single ? '## Tree' : '## Tree of ${snapshot.url ?? 'page'}');
      out.writeln();
      out.writeln('```');
      out.write(renderTree(snapshot, options: options.treeOptions, root: options.root));
      out.writeln('```');
    }
  }

  return out.toString();
}

/// The analysis as plain JSON-encodable data, for tools.
Map<String, Object?> analysisToJson(Analysis analysis, {String? root}) => {
  'pages': [
    for (final page in analysis.pages)
      {
        'url': page.url,
        'elements': page.elements,
        'instances': page.components,
        'classes': page.types,
        'reuseShare': double.parse(page.reuseShare.toStringAsFixed(3)),
      },
  ],
  'reuseShare': double.parse(analysis.reuseShare.toStringAsFixed(3)),
  'components': [
    for (final usage in analysis.types)
      {
        'name': usage.type.name,
        'origin': usage.type.origin.name,
        'package': ?usage.type.package,
        'source': ?shortLocation(usage.type, root: root),
        'instances': usage.instances,
        'pages': usage.pages,
        'ownElements': usage.ownElements,
        'inside': usage.containers,
      },
  ],
  'findings': [
    for (final finding in analysis.findings)
      {
        'kind': finding.kind.name,
        'shape': finding.shape,
        'minElements': finding.minElements,
        'maxElements': finding.maxElements,
        'identical': finding.identical,
        'occurrences': finding.occurrences.length,
        'components': finding.components,
        'inlineIn': finding.inlineOwners,
        'pages': finding.pages.toList(),
        'summary': describeFinding(finding),
      },
  ],
};
