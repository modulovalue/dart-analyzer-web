import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../plugin.dart';

// Links to the grammar file in the Dart SDK
const _grammarGitHubUrl = 'https://github.com/dart-lang/sdk/blob/main/tools/spec_parser/dart_spec_parser/Dart.g4';
const _grammarRawUrl = 'https://raw.githubusercontent.com/dart-lang/sdk/main/tools/spec_parser/dart_spec_parser/Dart.g4';

/// Plugin that displays the Dart ANTLR grammar file
class GrammarViewerPlugin extends Plugin {
  @override
  String get id => 'grammar_viewer';

  @override
  String get name => 'Grammar';

  @override
  String get icon => '📜';

  static String? _grammarContent;
  static bool _isLoading = false;

  @override
  Future<PluginResult> process(String sourceCode, PluginContext context) async {
    final stopwatch = Stopwatch()..start();

    // Load grammar content if not already loaded
    if (_grammarContent == null && !_isLoading) {
      _isLoading = true;
      _grammarContent = await _fetchGrammarContent();
      _isLoading = false;
    }

    stopwatch.stop();

    final html = _generateHtml();
    return PluginResult.success(html, processingTime: stopwatch.elapsed);
  }

  Future<String> _fetchGrammarContent() async {
    try {
      final response = await web.window.fetch(_grammarRawUrl.toJS).toDart;
      if (response.ok) {
        final text = await response.text().toDart;
        return text.toDart;
      }
    } catch (e) {
      // Fall back to embedded content on error
    }
    return _fallbackGrammar;
  }

  String _generateHtml() {
    final buffer = StringBuffer();
    buffer.writeln('<div class="grammar-viewer">');

    buffer.writeln('<div class="plugin-header">');
    buffer.writeln('<span class="plugin-badge">ANTLR4</span>');
    buffer.writeln('<span class="grammar-info">Dart.g4 v0.58 (Official Dart SDK)</span>');
    buffer.writeln('<a href="$_grammarGitHubUrl" target="_blank" class="grammar-link">View on GitHub ↗</a>');
    buffer.writeln('</div>');

    buffer.writeln('<div id="grammar-editor-container" class="grammar-editor-container"></div>');

    buffer.writeln('</div>');
    return buffer.toString();
  }

  @override
  void onActivate() {
    // Initialize the Monaco editor for the grammar after a short delay
    // to ensure the container is in the DOM
    Future.delayed(const Duration(milliseconds: 100), () {
      _initGrammarEditor();
    });
  }

  void _initGrammarEditor() {
    final container = web.document.getElementById('grammar-editor-container');
    if (container == null) return;

    // Check if editor already exists
    if (container.children.length > 0) return;

    final grammarContent = _escapeForJs(_grammarContent ?? '// Loading...');

    _eval('''
      (function() {
        var container = document.getElementById('grammar-editor-container');
        if (!container || container.children.length > 0) return;

        // Register ANTLR grammar language
        if (!monaco.languages.getLanguages().some(function(l) { return l.id === 'antlr4'; })) {
          monaco.languages.register({ id: 'antlr4' });
          monaco.languages.setMonarchTokensProvider('antlr4', {
            keywords: ['grammar', 'lexer', 'parser', 'options', 'tokens', 'channels', 'import', 'fragment', 'mode', 'returns', 'locals', 'throws', 'catch', 'finally'],
            tokenizer: {
              root: [
                [/\\/\\/.*/, 'comment'],
                [/\\/\\*/, 'comment', '@comment'],
                [/'[^']*'/, 'string'],
                [/[A-Z][a-zA-Z0-9_]*/, 'type'],
                [/[a-z][a-zA-Z0-9_]*/, { cases: { '@keywords': 'keyword', '@default': 'identifier' } }],
                [/[{}()\\[\\]|;:?*+]/, 'delimiter'],
                [/->/, 'operator'],
                [/\\{.*?\\}/, 'annotation'],
              ],
              comment: [
                [/[^\\/*]+/, 'comment'],
                [/\\*\\//, 'comment', '@pop'],
                [/[\\/*]/, 'comment']
              ],
            }
          });
        }

        // Calculate available height and set explicit pixel height
        var pluginContent = document.getElementById('plugin-content');
        var grammarViewer = container.parentElement;
        if (pluginContent && grammarViewer) {
          var contentRect = pluginContent.getBoundingClientRect();
          var headerHeight = grammarViewer.querySelector('.plugin-header').offsetHeight || 40;
          var availableHeight = contentRect.height - headerHeight - 60;
          container.style.height = Math.max(400, availableHeight) + 'px';
        } else {
          // Fallback: use viewport height
          container.style.height = (window.innerHeight - 250) + 'px';
        }

        window.grammarEditor = monaco.editor.create(container, {
          value: $grammarContent,
          language: 'antlr4',
          theme: 'vs-dark',
          fontSize: 12,
          fontFamily: "'Fira Code', Consolas, 'Courier New', monospace",
          minimap: { enabled: true },
          readOnly: true,
          automaticLayout: true,
          scrollBeyondLastLine: false,
          lineNumbers: 'on',
          wordWrap: 'off',
          folding: true
        });

        // Force layout after short delay
        setTimeout(function() {
          if (window.grammarEditor) {
            window.grammarEditor.layout();
          }
        }, 50);
      })();
    ''');
  }

  String _escapeForJs(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');
    return '`$escaped`';
  }
}

@JS('eval')
external JSAny? _eval(String code);

// Fallback grammar content if fetch fails
const _fallbackGrammar = r'''
// Failed to load grammar from GitHub.
// Please visit the link above to view the full Dart ANTLR grammar.
//
// The Dart.g4 grammar is the official ANTLR4 grammar for the Dart language,
// maintained by the Dart team at Google.
//
// Version: v0.58
// Features:
// - Full Dart language syntax support
// - Pattern matching and records
// - Extension types
// - Augmentation libraries
// - Null safety
// - And more...
''';
