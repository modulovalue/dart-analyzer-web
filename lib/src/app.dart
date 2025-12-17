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

/// Dart Code Analyzer - Browser-based Dart code analysis tool
class DartAnalyzerApp {
  final PluginRegistry plugins = PluginRegistry();
  final Set<String> _pluginErrors = {};

  String _currentCode = '';
  String? _activePluginId;
  Timer? _analyzeDebounce;

  DartAnalyzerApp() {
    plugins.register(TokenStreamPlugin());
    plugins.register(AstPlugin());
    plugins.register(AntlrTokenStreamPlugin());
    plugins.register(AntlrParseTreePlugin());
    plugins.register(GrammarViewerPlugin());
  }

  Future<void> init() async {
    _log('Initializing Dart Analyzer...');
    await _waitForMonaco();
    _createEditor();
    _setupPluginTabs();
    _setupEventHandlers();
    _scheduleAnalysis();
    _updateStatusBar();
    _log('Initialization complete');
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

    final initialCode = '''void main() {
  print('Hello, Dart!');

  for (int i = 0; i < 5; i++) {
    print('Count: \$i');
  }

  final greeting = greet('World');
  print(greeting);
}

String greet(String name) {
  return 'Hello, \$name!';
}

class Person {
  final String name;
  final int age;

  Person(this.name, this.age);

  void introduce() {
    print('I am \$name, \$age years old');
  }
}''';

    _currentCode = initialCode;

    // Create editor using raw JS to avoid string escaping issues
    final jsCode = '''
      window.dartEditor = monaco.editor.create(document.getElementById('editor-container'), {
        value: ${_toJsString(initialCode)},
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
