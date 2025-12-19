import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'plugin.dart';
import 'plugins/token_stream_plugin.dart';
import 'plugins/ast_plugin.dart';
import 'plugins/antlr_token_stream_plugin.dart';
import 'plugins/antlr_parse_tree_plugin.dart';
import 'plugins/grammar_viewer_plugin.dart';

// JS interop
@JS('monaco')
external JSObject? get _monaco;

@JS('eval')
external JSAny? _eval(String code);

@JS('globalThis')
external JSObject get _globalThis;

// Helper extension for JSObject property access
extension JSObjectHelper on JSObject {
  void setProperty(String key, JSAny? value) {
    _setProperty(this, key, value);
  }
}

@JS('Reflect.set')
external void _setProperty(JSObject obj, String key, JSAny? value);

/// Represents a node in the file tree (file or folder)
class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  final List<FileNode> children;
  String content;

  FileNode({
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.children = const [],
    this.content = '',
  });
}

/// Dart Code Analyzer - Browser-based Dart code analysis tool
class DartAnalyzerApp {
  final PluginRegistry plugins = PluginRegistry();
  final Set<String> _pluginErrors = {};

  String _currentCode = '';
  String? _activePluginId;
  Timer? _analyzeDebounce;

  late final List<FileNode> _fileTree;
  final Map<String, FileNode> _fileMap = {};
  String? _selectedFilePath;

  DartAnalyzerApp() {
    plugins.register(TokenStreamPlugin());
    plugins.register(AstPlugin());
    plugins.register(AntlrTokenStreamPlugin());
    plugins.register(AntlrParseTreePlugin());
    plugins.register(GrammarViewerPlugin());
    _initializeFileTree();
  }

  void _initializeFileTree() {
    _fileTree = [
      FileNode(
        name: 'lib',
        path: 'lib',
        isDirectory: true,
        children: [
          FileNode(
            name: 'main.dart',
            path: 'lib/main.dart',
            content: '''void main() {
  print('Hello, Dart!');
  final result = add(2, 3);
  print('2 + 3 = \$result');
}

int add(int a, int b) => a + b;''',
          ),
          FileNode(
            name: 'utils.dart',
            path: 'lib/utils.dart',
            content: '''String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

bool isEven(int n) => n % 2 == 0;''',
          ),
          FileNode(
            name: 'models',
            path: 'lib/models',
            isDirectory: true,
            children: [
              FileNode(
                name: 'person.dart',
                path: 'lib/models/person.dart',
                content: '''class Person {
  final String name;
  final int age;

  Person(this.name, this.age);

  void greet() => print('Hi, I am \$name');
}''',
              ),
              FileNode(
                name: 'animal.dart',
                path: 'lib/models/animal.dart',
                content: '''abstract class Animal {
  String get sound;
  void speak() => print(sound);
}

class Dog extends Animal {
  @override
  String get sound => 'Woof!';
}

class Cat extends Animal {
  @override
  String get sound => 'Meow!';
}''',
              ),
            ],
          ),
        ],
      ),
      FileNode(
        name: 'test',
        path: 'test',
        isDirectory: true,
        children: [
          FileNode(
            name: 'example_test.dart',
            path: 'test/example_test.dart',
            content: '''void main() {
  test('addition works', () {
    expect(2 + 2, equals(4));
  });
}''',
          ),
        ],
      ),
    ];

    void buildMap(List<FileNode> nodes) {
      for (final node in nodes) {
        _fileMap[node.path] = node;
        if (node.isDirectory) {
          buildMap(node.children);
        }
      }
    }
    buildMap(_fileTree);
  }

  Future<void> init() async {
    _log('Initializing Dart Analyzer...');
    await _waitForMonaco();
    _createEditor();
    _setupFileTree();
    _setupPluginTabs();
    _setupEventHandlers();
    _scheduleAnalysis();
    _updateStatusBar();
    _log('Initialization complete');
  }

  void _setupFileTree() {
    final treeContainer = web.document.getElementById('file-tree');
    if (treeContainer == null) return;

    String renderNode(FileNode node, {bool expanded = true}) {
      if (node.isDirectory) {
        final childrenHtml = node.children.map((c) => renderNode(c)).join('');
        return '''
          <div class="tree-folder${expanded ? ' expanded' : ''}" data-path="${node.path}">
            <div class="tree-item">
              <span class="tree-item-icon"></span>
              <span class="tree-item-name">${node.name}</span>
            </div>
            <div class="tree-children${expanded ? '' : ' collapsed'}">$childrenHtml</div>
          </div>
        ''';
      } else {
        return '''
          <div class="tree-file" data-path="${node.path}">
            <div class="tree-item">
              <span class="tree-item-icon"></span>
              <span class="tree-item-name">${node.name}</span>
            </div>
          </div>
        ''';
      }
    }

    final html = _fileTree.map((n) => renderNode(n)).join('');
    treeContainer.innerHTML = html.toJS;

    _setupTreeInteractions();

    // Select first file by default
    final firstFile = _findFirstFile(_fileTree);
    if (firstFile != null) {
      _selectFile(firstFile.path);
    }
  }

  FileNode? _findFirstFile(List<FileNode> nodes) {
    for (final node in nodes) {
      if (!node.isDirectory) return node;
      final found = _findFirstFile(node.children);
      if (found != null) return found;
    }
    return null;
  }

  void _setupTreeInteractions() {
    // Folder toggle
    final folders = web.document.querySelectorAll('.tree-folder > .tree-item');
    for (int i = 0; i < folders.length; i++) {
      final item = folders.item(i) as web.HTMLElement;
      item.onClick.listen((e) {
        final folder = item.parentElement;
        if (folder != null) {
          folder.classList.toggle('expanded');
          final children = folder.querySelector('.tree-children') as web.HTMLElement?;
          children?.classList.toggle('collapsed');
        }
      });
    }

    // File selection
    final files = web.document.querySelectorAll('.tree-file > .tree-item');
    for (int i = 0; i < files.length; i++) {
      final item = files.item(i) as web.HTMLElement;
      item.onClick.listen((e) {
        final fileNode = item.parentElement as web.HTMLElement?;
        final path = fileNode?.dataset['path'];
        if (path != null) {
          _selectFile(path);
        }
      });
    }
  }

  void _selectFile(String path) {
    final file = _fileMap[path];
    if (file == null || file.isDirectory) return;

    // Save current file content
    if (_selectedFilePath != null) {
      final currentFile = _fileMap[_selectedFilePath!];
      if (currentFile != null) {
        final result = _eval('window.dartEditor ? window.dartEditor.getValue() : ""');
        currentFile.content = (result as JSString?)?.toDart ?? '';
      }
    }

    _selectedFilePath = path;
    _currentCode = file.content;

    // Update selection UI
    final allItems = web.document.querySelectorAll('.tree-item');
    for (int i = 0; i < allItems.length; i++) {
      (allItems.item(i) as web.HTMLElement).classList.remove('selected');
    }

    final selected = web.document.querySelector('[data-path="$path"] > .tree-item') as web.HTMLElement?;
    selected?.classList.add('selected');

    // Update editor title
    final title = web.document.getElementById('editor-title') as web.HTMLElement?;
    if (title != null) {
      title.innerText = file.name;
    }

    // Update editor content
    _eval('if (window.dartEditor) window.dartEditor.setValue(${_toJsString(file.content)})');
    _scheduleAnalysis();
  }

  Future<void> _waitForMonaco() async {
    _log('Waiting for Monaco editor...');
    while (_monaco == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _log('Monaco loaded');
  }

  void _createEditor() {
    _registerDartLanguage();

    // Create editor with empty content - file tree will populate it
    final jsCode = '''
      window.dartEditor = monaco.editor.create(document.getElementById('editor-container'), {
        value: '',
        language: 'dart',
        theme: 'vs-dark',
        fontSize: 14,
        fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
        minimap: { enabled: false },
        automaticLayout: true,
        scrollBeyondLastLine: false,
        lineNumbers: 'on',
        renderLineHighlight: 'line',
        tabSize: 2,
      });

      window.dartEditor.getModel().onDidChangeContent(function() {
        if (window.onDartCodeChanged) window.onDartCodeChanged();
      });
    ''';
    _eval(jsCode);

    // Set up change callback
    _globalThis.setProperty('onDartCodeChanged', (() { _onCodeChanged(); }).toJS);

    _log('Editor created');
  }

  void _registerDartLanguage() {
    _eval('''
      // Add custom CSS for highlighting
      var style = document.createElement('style');
      style.textContent = '.highlight-range-inline { background-color: rgba(255, 255, 0, 0.4) !important; } .highlight-range-line { background-color: rgba(255, 255, 0, 0.15) !important; }';
      document.head.appendChild(style);

      monaco.languages.register({ id: 'dart' });
      monaco.languages.setMonarchTokensProvider('dart', {
        keywords: [
          'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
          'class', 'const', 'continue', 'default', 'do', 'dynamic', 'else', 'enum',
          'export', 'extends', 'external', 'factory', 'false', 'final', 'finally',
          'for', 'Function', 'get', 'if', 'implements', 'import', 'in', 'interface',
          'is', 'late', 'library', 'new', 'null', 'on', 'operator', 'part', 'return',
          'set', 'static', 'super', 'switch', 'this', 'throw', 'true', 'try', 'typedef',
          'var', 'void', 'while', 'with', 'yield'
        ],
        typeKeywords: ['int', 'double', 'String', 'bool', 'List', 'Map', 'Set', 'Future', 'Stream', 'Object', 'dynamic', 'void'],
        tokenizer: {
          root: [
            [/[a-zA-Z_][\\w]*/, { cases: { '@keywords': 'keyword', '@typeKeywords': 'type', '@default': 'identifier' } }],
            [/[0-9]+(\\.[0-9]+)?/, 'number'],
            [/\\/\\/.*/, 'comment'],
            [/\\/\\*/, 'comment', '@comment'],
            [/"([^"\\\\]|\\\\.)*"/, 'string'],
            [/'([^'\\\\]|\\\\.)*'/, 'string'],
            [/[;,.]/, 'delimiter'],
          ],
          comment: [
            [/[^\\/*]+/, 'comment'],
            [/\\*\\//, 'comment', '@pop'],
            [/[\\/*]/, 'comment']
          ],
        }
      });
    ''');
  }

  void _setupPluginTabs() {
    final tabsContainer = web.document.getElementById('plugin-tabs');
    if (tabsContainer == null) return;

    tabsContainer.innerHTML = ''.toJS;

    for (final plugin in plugins.plugins) {
      final tab = web.document.createElement('button') as web.HTMLButtonElement;
      tab.className = 'plugin-tab';
      tab.dataset['pluginId'] = plugin.id;
      tab.innerHTML = '<span class="tab-icon">${plugin.icon}</span> <span class="tab-name">${plugin.name}</span><span class="tab-error-icon"></span>'.toJS;
      tab.onClick.listen((_) => _activatePlugin(plugin.id));
      tabsContainer.appendChild(tab);
    }

    if (plugins.plugins.isNotEmpty) {
      _activatePlugin(plugins.plugins.first.id);
    }
  }

  void _activatePlugin(String pluginId) {
    _activePluginId = pluginId;

    final tabs = web.document.querySelectorAll('.plugin-tab');
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs.item(i) as web.HTMLElement;
      if (tab.dataset['pluginId'] == pluginId) {
        tab.classList.add('active');
      } else {
        tab.classList.remove('active');
      }
    }

    _runActivePlugin();
  }

  Future<void> _runActivePlugin() async {
    if (_activePluginId == null) return;

    final plugin = plugins.getPlugin(_activePluginId!);
    if (plugin == null) return;

    final contentContainer = web.document.getElementById('plugin-content');
    if (contentContainer == null) return;

    contentContainer.innerHTML = '<div class="plugin-loading">Analyzing...</div>'.toJS;

    final context = PluginContext(log: _log);

    try {
      final result = await plugin.process(_currentCode, context);
      if (result.success) {
        if (result.hasIssues) {
          _pluginErrors.add(plugin.id);
          _updateTabErrorState(plugin.id, true);
        } else {
          _pluginErrors.remove(plugin.id);
          _updateTabErrorState(plugin.id, false);
        }
        var html = result.content;
        if (result.processingTime != null) {
          html += '<div class="processing-time">Processed in ${result.processingTime!.inMilliseconds}ms</div>';
        }
        contentContainer.innerHTML = html.toJS;
        _setupPluginInteractions();
        plugin.onActivate();
      } else {
        _pluginErrors.add(plugin.id);
        _updateTabErrorState(plugin.id, true);
        contentContainer.innerHTML = '<div class="plugin-error">${_escapeHtml(result.error ?? 'Unknown error')}</div>'.toJS;
      }
    } catch (e) {
      _pluginErrors.add(plugin.id);
      _updateTabErrorState(plugin.id, true);
      contentContainer.innerHTML = '<div class="plugin-error">Plugin error: ${_escapeHtml(e.toString())}</div>'.toJS;
    }
  }

  void _updateTabErrorState(String pluginId, bool hasError) {
    final tabs = web.document.querySelectorAll('.plugin-tab');
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs.item(i) as web.HTMLElement;
      if (tab.dataset['pluginId'] == pluginId) {
        final errorIcon = tab.querySelector('.tab-error-icon') as web.HTMLElement?;
        if (errorIcon != null) {
          errorIcon.innerHTML = (hasError ? ' ⚠️' : '').toJS;
        }
        if (hasError) {
          tab.classList.add('has-error');
        } else {
          tab.classList.remove('has-error');
        }
        break;
      }
    }
  }

  void _setupPluginInteractions() {
    _eval('''
      // Tree node expand/collapse
      document.querySelectorAll('.ast-node.expandable .node-toggle').forEach(function(toggle) {
        toggle.onclick = function(e) {
          var node = e.target.parentElement;
          var children = node.querySelector('.node-children');
          if (children) {
            children.classList.toggle('collapsed');
            e.target.textContent = children.classList.contains('collapsed') ? '▶' : '▼';
          }
        };
      });

      // Hover highlighting for tokens and tree nodes
      if (!window.highlightDecorations) {
        window.highlightDecorations = [];
      }

      window.highlightRange = function(offset, length) {
        if (!window.dartEditor || offset === undefined || length === undefined) return;
        var model = window.dartEditor.getModel();
        if (!model) return;

        var startPos = model.getPositionAt(parseInt(offset));
        var endPos = model.getPositionAt(parseInt(offset) + parseInt(length));

        window.highlightDecorations = window.dartEditor.deltaDecorations(window.highlightDecorations, [{
          range: new monaco.Range(startPos.lineNumber, startPos.column, endPos.lineNumber, endPos.column),
          options: {
            inlineClassName: 'highlight-range-inline',
            className: 'highlight-range-line',
            overviewRuler: {
              color: '#ffff00',
              position: monaco.editor.OverviewRulerLane.Full
            }
          }
        }]);

        // Also scroll to the highlighted range
        window.dartEditor.revealRangeInCenter(new monaco.Range(startPos.lineNumber, startPos.column, endPos.lineNumber, endPos.column));
      };

      window.clearHighlight = function() {
        if (!window.dartEditor) return;
        window.highlightDecorations = window.dartEditor.deltaDecorations(window.highlightDecorations, []);
      };

      // Add hover handlers to all highlightable elements
      document.querySelectorAll('[data-offset][data-length]').forEach(function(el) {
        el.addEventListener('mouseenter', function() {
          var offset = this.getAttribute('data-offset');
          var length = this.getAttribute('data-length');
          window.highlightRange(offset, length);
          this.classList.add('highlight-active');
        });
        el.addEventListener('mouseleave', function() {
          window.clearHighlight();
          this.classList.remove('highlight-active');
        });
      });
    ''');
  }

  void _setupEventHandlers() {
    // Info modal handlers
    web.document.getElementById('info-btn')?.onClick.listen((_) => _showInfoModal());
    web.document.getElementById('close-modal')?.onClick.listen((_) => _hideInfoModal());
    web.document.getElementById('info-modal')?.onClick.listen((e) {
      // Close modal when clicking outside content
      if ((e.target as web.Element?)?.id == 'info-modal') {
        _hideInfoModal();
      }
    });
  }

  void _showInfoModal() {
    web.document.getElementById('info-modal')?.classList.remove('hidden');
  }

  void _hideInfoModal() {
    web.document.getElementById('info-modal')?.classList.add('hidden');
  }

  void _onCodeChanged() {
    final result = _eval('window.dartEditor ? window.dartEditor.getValue() : ""');
    _currentCode = (result as JSString?)?.toDart ?? '';
    _scheduleAnalysis();
  }

  void _scheduleAnalysis() {
    _analyzeDebounce?.cancel();
    _analyzeDebounce = Timer(const Duration(milliseconds: 500), () {
      _runAllPluginsForErrors();
      _runActivePlugin();
    });
  }

  Future<void> _runAllPluginsForErrors() async {
    final context = PluginContext(log: _log);

    for (final plugin in plugins.plugins) {
      // Skip grammar viewer - it doesn't analyze code
      if (plugin.id == 'grammar_viewer') continue;
      // Skip active plugin - it will be run separately with UI update
      if (plugin.id == _activePluginId) continue;

      try {
        final result = await plugin.process(_currentCode, context);
        if (result.hasIssues || !result.success) {
          _pluginErrors.add(plugin.id);
          _updateTabErrorState(plugin.id, true);
        } else {
          _pluginErrors.remove(plugin.id);
          _updateTabErrorState(plugin.id, false);
        }
      } catch (e) {
        _pluginErrors.add(plugin.id);
        _updateTabErrorState(plugin.id, true);
      }
    }
  }

  void _updateStatusBar() {
    final statusBar = web.document.getElementById('status-bar');
    if (statusBar == null) return;
    statusBar.className = 'status-bar';
    statusBar.innerHTML = '<span class="status-text">Ready</span>'.toJS;
  }

  void _log(String message) {
    web.console.log('[DartAnalyzer] $message'.toJS);
  }

  String _toJsString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  String _escapeHtml(String s) {
    return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }
}
