import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/analysis.dart';
import '../core/report.dart';
import '../core/snapshot.dart';
import 'dom.dart';
import 'state.dart';

/// The docked panel: controls, the component tree, the inventory, the reuse
/// findings and details about the selection.
class Panel {
  Panel(
    this.state,
    web.Node root, {
    required this.onTurnOff,
    required this.onFront,
    required this.onResetCamera,
    required this.snapshotJson,
    this.editorUrl = 'vscode://file/{file}:{line}',
    this.projectRoot,
  }) {
    _build(root);
  }

  final OverlayState state;
  final void Function() onTurnOff;
  final void Function() onFront;
  final void Function() onResetCamera;

  /// Returns the snapshot with rectangles, as JSON text.
  final String Function() snapshotJson;

  /// Link template for opening a source file, with `{file}` and `{line}`.
  final String editorUrl;

  /// Directory that file paths are shown relative to.
  final String? projectRoot;

  late final web.HTMLElement _panel;
  late final web.HTMLElement _reopen;
  late final web.HTMLElement _body;
  late final web.HTMLElement _details;
  late final web.HTMLElement _status;
  late final web.HTMLElement _layersBar;
  late final web.HTMLElement _depthLabel;
  late final web.HTMLInputElement _depth;
  late final web.HTMLInputElement _search;
  final Map<String, web.HTMLElement> _modeButtons = {};
  final Map<String, web.HTMLElement> _scopeButtons = {};
  final Map<String, web.HTMLElement> _tabButtons = {};
  late final web.HTMLElement _pickButton;
  late final web.HTMLElement _texturesButton;

  final Map<Box, web.HTMLElement> _treeRows = Map.identity();
  final Map<String, web.HTMLElement> _typeRows = {};
  final Map<MarkupFinding, web.HTMLElement> _findingRows = Map.identity();
  String _bodyKey = '';

  web.HTMLElement _button(String label, void Function() onClick, {String? cls, String? title}) {
    final button = el<web.HTMLElement>('button', cls: cls, text: label, title: title);
    on(button, 'click', (_) => onClick());
    return button;
  }

  void _build(web.Node root) {
    _pickButton = _button(
      'Pick',
      () => state.update(() => state.picking = !state.picking),
      title: 'Click a component on the page to select it (or Alt-click any time)',
    );

    final modes = el<web.HTMLElement>('div', cls: 'seg');
    for (final (name, label, mode) in [('flat', '2D', ViewMode.flat), ('layers', '3D', ViewMode.layers)]) {
      modes.appendChild(_modeButtons[name] = _button(label, () => state.setMode(mode)));
    }

    final scopes = el<web.HTMLElement>('div', cls: 'seg');
    for (final (name, label, title) in [
      ('project', 'Project', 'Components written in this repository'),
      ('packages', '+ Packages', 'Also components from hosted packages'),
      ('all', '+ Framework', 'Everything, framework internals included'),
    ]) {
      scopes.appendChild(_scopeButtons[name] = _button(label, () => state.setScope(name), title: title));
    }

    _search = el<web.HTMLInputElement>('input', attrs: {'type': 'search', 'placeholder': 'Find a component'});
    on(_search, 'input', (_) => state.update(() => state.query = _search.value.trim()));

    _depth = el<web.HTMLInputElement>('input', attrs: {'type': 'range', 'min': '0', 'step': '1'});
    _depthLabel = el('span', cls: 'label');
    on(_depth, 'input', (_) {
      final value = int.parse(_depth.value);
      state.update(() => state.maxDepth = value >= state.deepest ? null : value);
    });

    final separation = el<web.HTMLInputElement>(
      'input',
      attrs: {'type': 'range', 'min': '0', 'max': '160', 'step': '2', 'value': '${state.separation.round()}'},
    );
    on(separation, 'input', (_) => state.update(() => state.separation = double.parse(separation.value)));
    _layersBar = el(
      'div',
      cls: 'bar',
      children: [
        el('span', cls: 'label', text: 'Separation'),
        separation,
        _texturesButton = _button(
          'Pixels',
          () => state.update(() => state.textures = !state.textures),
          title: 'Show the page itself on the layers, not just their outlines',
        ),
        _button('Front', onFront, title: 'Look at the page straight on'),
        _button('Reset', onResetCamera, title: 'Back to the starting view'),
      ],
    );

    final tabs = el<web.HTMLElement>('div', cls: 'tabs');
    for (final (name, label) in [('tree', 'Tree'), ('components', 'Components'), ('reuse', 'Reuse')]) {
      tabs.appendChild(_tabButtons[name] = _button(label, () => state.update(() => state.tab = name)));
    }

    _body = el('div', cls: 'body');
    _details = el('div', cls: 'details');
    _status = el('span', cls: 'label');

    _panel = el(
      'div',
      cls: 'panel',
      children: [
        el(
          'div',
          cls: 'bar',
          children: [
            el('span', cls: 'title', text: 'Anatomy'),
            modes,
            _pickButton,
            _button(
              '\u21c4',
              () => state.update(() => state.panelLeft = !state.panelLeft),
              cls: 'icon',
              title: 'Move this panel to the other side',
            ),
            _button(
              '\u2013',
              () => state.update(() => state.panelOpen = false),
              cls: 'icon',
              title: 'Minimise this panel. Alt+Shift+A hides the whole overlay.',
            ),
            _button('Off', onTurnOff, cls: 'danger', title: 'Turn anatomy off and reload the page'),
          ],
        ),
        el('div', cls: 'bar', children: [scopes]),
        el(
          'div',
          cls: 'bar',
          children: [
            _search,
            el('span', cls: 'label', text: 'Depth'),
            _depth,
            _depthLabel,
          ],
        ),
        _layersBar,
        tabs,
        _body,
        _details,
        el(
          'div',
          cls: 'foot',
          children: [
            _button(
              'Copy report',
              () => _copy(renderReport(state.analysis, options: ReportOptions(root: projectRoot))),
              title: 'Markdown: components, reuse findings and the tree',
            ),
            _button('Copy JSON', () => _copy(snapshotJson()), title: 'The page tree with positions, for tools'),
            _status,
          ],
        ),
      ],
    );

    _reopen = _button('Anatomy', state.reopen, cls: 'reopen', title: 'Show the anatomy panel (Alt+Shift+A)');
    root
      ..appendChild(_panel)
      ..appendChild(_reopen);
  }

  void _copy(String text) {
    unawaited(
      web.window.navigator.clipboard
          .writeText(text)
          .toDart
          .then(
            (_) => _flash('Copied'),
            onError: (Object _) => _flash('Copy was blocked'),
          ),
    );
  }

  void _flash(String message) {
    final previous = _status.textContent;
    _status.textContent = message;
    web.window.setTimeout((() => _status.textContent = previous).toJS, 1400.toJS);
  }

  /// Brings the panel in line with the state.
  void render() {
    final shown = state.mode != ViewMode.hidden;
    final open = shown && state.panelOpen;
    _panel.style.display = open ? '' : 'none';
    _panel.classList.toggle('left', state.panelLeft);
    _reopen.style.display = open ? 'none' : '';
    _reopen.classList.toggle('left', state.panelLeft);
    if (!open) return;

    _modeButtons.forEach((name, button) => button.classList.toggle('active', state.mode.name == name));
    _scopeButtons.forEach((name, button) => button.classList.toggle('active', state.scopeName == name));
    _tabButtons.forEach((name, button) => button.classList.toggle('active', state.tab == name));
    _pickButton.classList.toggle('active', state.picking);
    _texturesButton.classList.toggle('active', state.textures);
    _layersBar.style.display = state.mode == ViewMode.layers ? '' : 'none';

    final deepest = state.deepest;
    _depth
      ..max = '$deepest'
      ..value = '${state.maxDepth ?? deepest}';
    _depthLabel.textContent = state.maxDepth == null ? 'all' : '${state.maxDepth! + 1}';

    final dom = state.dom;
    _status.textContent = dom.matched == dom.expected
        ? '${state.boxes.length} components'
        : '${dom.matched}/${dom.expected} elements located';
    _status.title = 'Elements of the server-rendered tree found in the page';

    // Rebuild the list only when what it shows changed; hovering must not.
    final key = '${state.tab}|${state.scopeName}|${state.maxDepth}|${state.query}|${identityHashCode(state.snapshot)}';
    if (key != _bodyKey) {
      _bodyKey = key;
      _renderBody();
    }
    _highlightRows();
    _renderDetails();
  }

  void _renderBody() {
    clear(_body);
    _treeRows.clear();
    _typeRows.clear();
    _findingRows.clear();
    switch (state.tab) {
      case 'components':
        _renderComponents();
      case 'reuse':
        _renderReuse();
      default:
        _renderTree();
    }
  }

  web.HTMLElement _swatch(int hue) => el<web.HTMLElement>('span', cls: 'sw')..style.setProperty('--h', '$hue');

  void _renderTree() {
    final boxes = state.boxes.where((box) => state.withinDepth(box) && state.matchesQuery(box)).toList();
    if (boxes.isEmpty) {
      _body.appendChild(el('div', cls: 'note', text: state.boxes.isEmpty ? 'No components in scope.' : 'No match.'));
      return;
    }
    for (final box in boxes) {
      final row = el<web.HTMLElement>(
        'div',
        cls: 'row',
        children: [
          _swatch(state.hueOf(box)),
          el('span', cls: 'name', text: state.labelOf(box)),
          if (box.chain.any((node) => node.client != null)) el('span', cls: 'pill', text: 'client'),
          if (box.rect == null)
            el('span', cls: 'pill', text: 'no box', title: 'Has no area on the page right now: hidden, or only text'),
        ],
      );
      // Without a search the indentation shows nesting; search results are flat.
      row.style.paddingLeft = px(10 + (state.query.isEmpty ? box.depth * 12 : 0));
      on(row, 'click', (_) => _selectAndReveal(box));
      on(row, 'mouseenter', (_) => state.hover(box));
      on(row, 'mouseleave', (_) => state.hover(null));
      _body.appendChild(row);
      _treeRows[box] = row;
    }
  }

  void _renderComponents() {
    final types = state.analysis.types.where((usage) {
      return state.query.isEmpty || usage.type.name.toLowerCase().contains(state.query.toLowerCase());
    }).toList();
    if (types.isEmpty) {
      _body.appendChild(el('div', cls: 'note', text: 'No components in scope.'));
      return;
    }
    for (final usage in types) {
      final type = usage.type;
      final row = el<web.HTMLElement>(
        'div',
        cls: 'row',
        title: _location(type) ?? type.library ?? '',
        children: [
          _swatch(hueFor(type.id)),
          el('span', cls: 'name', text: type.name),
          if (type.origin != Origin.project && type.origin != Origin.unknown)
            el('span', cls: 'pill', text: type.package ?? type.origin.name),
          el('span', cls: 'count', text: '×${usage.instances}'),
        ],
      );
      on(row, 'click', (_) {
        state.selectType(type.id);
        _revealFirstOfType(type.id);
      });
      _body.appendChild(row);
      _typeRows[type.id] = row;
    }
  }

  void _renderReuse() {
    final analysis = state.analysis;
    final page = analysis.pages.single;
    final share = (page.reuseShare * 100).round();
    _body.appendChild(
      el(
        'div',
        cls: 'note',
        text:
            '$share% of this page\'s ${page.elements} elements come from components used more than once here. '
            'Run the inspect command over several pages for totals across the site.',
      ),
    );

    _body.appendChild(el('div', cls: 'section', text: 'Repeated markup'));
    if (analysis.findings.isEmpty) {
      _body.appendChild(el('div', cls: 'note', text: 'Nothing found on this page.'));
    }
    for (final finding in analysis.findings) {
      final label = switch (finding.kind) {
        FindingKind.duplicatesComponent => 'Duplicates a component',
        FindingKind.twinComponents => 'Twin components',
        FindingKind.repeatedInline => 'Repeated inline',
      };
      final row = el<web.HTMLElement>(
        'div',
        cls: 'finding',
        children: [
          el('span', cls: 'kind ${finding.kind.name}', text: label),
          el('div', text: describeFinding(finding).replaceAll('`', '')),
        ],
      );
      on(row, 'click', (_) {
        state.selectFinding(finding);
        if (state.selectedFinding != null) _revealElement(finding.occurrences.first.node);
      });
      _body.appendChild(row);
      _findingRows[finding] = row;
    }

    final oneOffs = analysis.oneOffs.where((usage) => usage.ownElements >= 5).take(6).toList();
    if (oneOffs.isNotEmpty) {
      _body.appendChild(el('div', cls: 'section', text: 'Where inline markup accumulates'));
      for (final usage in oneOffs) {
        final row = el<web.HTMLElement>(
          'div',
          cls: 'row',
          children: [
            _swatch(hueFor(usage.type.id)),
            el('span', cls: 'name', text: usage.type.name),
            el('span', cls: 'count', text: '${usage.ownElements} elements'),
          ],
        );
        on(row, 'click', (_) {
          state.selectType(usage.type.id);
          _revealFirstOfType(usage.type.id);
        });
        _body.appendChild(row);
      }
    }
  }

  void _highlightRows() {
    final focus = state.focus;
    _treeRows.forEach((box, row) {
      row.classList
        ..toggle('on', identical(box, state.hovered))
        ..toggle('sel', identical(box, state.selected))
        ..toggle(
          'same',
          focus != null
              ? state.sharesType(box, focus)
              : state.selectedType != null && state.hasType(box, state.selectedType!),
        );
    });
    _typeRows.forEach((id, row) {
      row.classList
        ..toggle('sel', id == state.selectedType)
        ..toggle('on', focus != null && state.hasType(focus, id));
    });
    _findingRows.forEach((finding, row) => row.classList.toggle('sel', identical(finding, state.selectedFinding)));
  }

  void _selectAndReveal(Box box) {
    state.select(box);
    if (state.mode == ViewMode.flat && box.hosts.isNotEmpty) _scrollTo(box.hosts.first);
  }

  void _revealFirstOfType(String typeId) {
    if (state.selectedType == null || state.mode != ViewMode.flat) return;
    for (final box in state.boxes) {
      if (state.hasType(box, typeId) && box.hosts.isNotEmpty) {
        _scrollTo(box.hosts.first);
        return;
      }
    }
  }

  void _revealElement(AnatomyNode node) {
    if (state.mode != ViewMode.flat) return;
    if (state.dom.elementOf(node.id) case final element?) _scrollTo(element);
  }

  void _scrollTo(web.Element element) {
    final box = element.getBoundingClientRect();
    final visible = box.top >= 0 && box.bottom <= web.window.innerHeight;
    if (!visible) element.scrollIntoView(web.ScrollIntoViewOptions(block: 'center', behavior: 'smooth'));
  }

  String? _location(ComponentType type) => shortLocation(type, root: projectRoot);

  web.HTMLElement _sourceLink(ComponentType type) {
    final location = _location(type);
    if (location == null) return el('span', cls: 'dim', text: 'source unknown');
    final file = type.file;
    if (file == null) return el('span', cls: 'dim', text: location);
    final href = editorUrl.replaceAll('{file}', Uri.encodeFull(file)).replaceAll('{line}', '${type.line ?? 1}');
    return el('a', text: location, title: 'Open in the editor', attrs: {'href': href});
  }

  void _renderDetails() {
    clear(_details);
    final box = state.selected ?? state.hovered;
    if (box != null) {
      _details.appendChild(
        el(
          'h4',
          children: [
            _swatch(state.hueOf(box)),
            web.Text(state.labelOf(box)),
            if (box.chain.any((node) => node.client != null))
              el('span', cls: 'pill', text: 'client', title: 'Hydrated in the browser'),
          ],
        ),
      );
      for (final node in box.chain) {
        final type = state.typeOf(node);
        final usage = state.analysis.usageOf(type.id);
        _details.appendChild(
          el(
            'p',
            children: [
              if (box.chain.length > 1) web.Text('${type.name}: '),
              _sourceLink(type),
              web.Text(usage == null ? '' : ' · ×${usage.instances} on this page'),
            ],
          ),
        );
        if (node.key != null) _details.appendChild(el('p', text: 'Key ${node.key}'));
      }
      if (box.rect case final rect?) {
        _details.appendChild(el('p', text: '${rect.width.round()} × ${rect.height.round()} px'));
      } else {
        _details.appendChild(el('p', text: 'No area on the page.'));
      }
      final ancestors = box.ancestors.toList();
      if (ancestors.isNotEmpty) {
        final line = el<web.HTMLElement>('p', children: [web.Text('Inside ')]);
        for (final (index, ancestor) in ancestors.indexed) {
          final link = el<web.HTMLElement>('a', text: state.typeOf(ancestor.node).name);
          on(link, 'click', (_) => _selectAndReveal(ancestor));
          line.appendChild(link);
          if (index < ancestors.length - 1) line.appendChild(web.Text(' ‹ '));
        }
        _details.appendChild(line);
      }
      return;
    }

    if (state.selectedType case final id?) {
      final usage = state.analysis.usageOf(id);
      if (usage != null) {
        final containers = usage.containers.entries
            .map(
              (entry) => '${entry.key.isEmpty ? 'page root' : entry.key}${entry.value > 1 ? ' ×${entry.value}' : ''}',
            )
            .join(', ');
        _details
          ..appendChild(el('h4', children: [_swatch(hueFor(id)), web.Text(usage.type.name)]))
          ..appendChild(el('p', children: [_sourceLink(usage.type)]))
          ..appendChild(el('p', text: '${usage.instances} on this page, writing ${usage.ownElements} elements itself.'))
          ..appendChild(el('p', text: 'Inside $containers'));
        return;
      }
    }

    if (state.selectedFinding case final finding?) {
      _details
        ..appendChild(el('h4', text: 'Repeated markup'))
        ..appendChild(el('p', children: [el('code', text: finding.shape)]))
        ..appendChild(el('p', text: 'Red dashes: written inline. Green: rendered by a component.'));
      return;
    }

    _details.appendChild(
      el(
        'p',
        text: state.mode == ViewMode.layers
            ? 'Click a layer to select it.'
            : 'Move over the page to see what each area is. Alt-click, or use Pick, to select.',
      ),
    );
  }
}
