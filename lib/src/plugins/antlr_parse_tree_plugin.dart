import 'package:antlr4/antlr4.dart';
import '../antlr/DartLexer.dart';
import '../antlr/DartParser.dart';
import '../plugin.dart';

/// Plugin that displays the ANTLR parse tree
class AntlrParseTreePlugin extends Plugin {
  @override
  String get id => 'antlr_parse_tree';

  @override
  String get name => 'ANTLR Tree';

  @override
  String get icon => '🌲';

  @override
  Future<PluginResult> process(String sourceCode, PluginContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      final input = InputStream.fromString(sourceCode);
      final lexer = DartLexer(input);
      final tokenStream = CommonTokenStream(lexer);
      final parser = DartParser(tokenStream);

      // Collect errors
      final errors = <String>[];
      final errorListener = _CollectingErrorListener(errors);
      parser.removeErrorListeners();
      parser.addErrorListener(errorListener);

      // Parse starting from libraryDeclaration (the main entry point)
      final tree = parser.libraryDeclaration();

      stopwatch.stop();

      final html = _generateHtml(tree, parser, errors);
      return PluginResult.success(html, processingTime: stopwatch.elapsed, hasIssues: errors.isNotEmpty);
    } catch (e, stack) {
      stopwatch.stop();
      return PluginResult.error('ANTLR Parsing failed: $e\n$stack');
    }
  }

  String _generateHtml(ParserRuleContext tree, DartParser parser, List<String> errors) {
    final buffer = StringBuffer();
    buffer.writeln('<div class="ast-view antlr-tree">');

    buffer.writeln('<div class="plugin-header">');
    buffer.writeln('<span class="plugin-badge">ANTLR4</span>');
    buffer.writeln('<span class="grammar-info">Dart.g4 v0.58 (Official Dart SDK)</span>');
    buffer.writeln('</div>');

    // Show errors if any
    if (errors.isNotEmpty) {
      buffer.writeln('<div class="ast-errors">');
      buffer.writeln('<h4>Parse Errors (${errors.length})</h4>');
      buffer.writeln('<ul>');
      for (final error in errors) {
        buffer.writeln('<li class="error-item">${_escapeHtml(error)}</li>');
      }
      buffer.writeln('</ul></div>');
    }

    // Show parse tree
    buffer.writeln('<div class="ast-tree">');
    _writeNode(buffer, tree, parser, 0);
    buffer.writeln('</div>');

    buffer.writeln('</div>');
    return buffer.toString();
  }

  void _writeNode(StringBuffer buffer, ParseTree node, DartParser parser, int depth) {
    if (node is TerminalNode) {
      // Leaf node (token)
      final token = node.symbol;
      if (token.type != Token.EOF) {
        final tokenName = parser.vocabulary.getSymbolicName(token.type) ??
                         parser.vocabulary.getLiteralName(token.type) ??
                         'T__${token.type}';
        final length = token.stopIndex - token.startIndex + 1;
        buffer.writeln('<div class="ast-node leaf node-literal" data-depth="$depth" data-offset="${token.startIndex}" data-length="$length">');
        buffer.writeln('<span class="node-toggle">○</span>');
        buffer.writeln('<span class="node-type terminal">$tokenName</span>');
        buffer.writeln('<span class="node-value">${_escapeHtml(token.text ?? '')}</span>');
        buffer.writeln('<span class="node-location">[${token.line}:${token.charPositionInLine}]</span>');
        buffer.writeln('</div>');
      }
    } else if (node is ParserRuleContext) {
      // Non-terminal node (rule)
      final ruleName = parser.ruleNames[node.ruleIndex];
      final hasChildren = node.childCount > 0;
      final expandClass = hasChildren ? 'expandable' : 'leaf';
      final nodeClass = _getNodeClass(ruleName);

      // Calculate offset and length for the rule
      final startToken = node.start;
      final stopToken = node.stop;
      String dataAttrs = '';
      if (startToken != null && stopToken != null) {
        final offset = startToken.startIndex;
        final length = stopToken.stopIndex - startToken.startIndex + 1;
        dataAttrs = 'data-offset="$offset" data-length="$length"';
      }

      buffer.writeln('<div class="ast-node $expandClass $nodeClass" data-depth="$depth" $dataAttrs>');
      buffer.writeln('<span class="node-toggle">${hasChildren ? "▶" : "○"}</span>');
      buffer.writeln('<span class="node-type">$ruleName</span>');

      // Add location info
      if (startToken != null) {
        buffer.writeln('<span class="node-location">[${startToken.line ?? '?'}:${startToken.charPositionInLine}]</span>');
      }

      if (hasChildren) {
        buffer.writeln('<div class="node-children collapsed">');
        for (int i = 0; i < node.childCount; i++) {
          final child = node.getChild(i);
          if (child != null) {
            _writeNode(buffer, child, parser, depth + 1);
          }
        }
        buffer.writeln('</div>');
      }

      buffer.writeln('</div>');
    }
  }

  String _getNodeClass(String ruleName) {
    final lower = ruleName.toLowerCase();
    if (lower.contains('declaration')) return 'node-declaration';
    if (lower.contains('statement')) return 'node-statement';
    if (lower.contains('expression')) return 'node-expression';
    if (lower.contains('literal')) return 'node-literal';
    if (lower.contains('identifier')) return 'node-identifier';
    if (lower.contains('type')) return 'node-type';
    if (lower.contains('pattern')) return 'node-pattern';
    if (lower.contains('parameter')) return 'node-parameter';
    return 'node-default';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class _CollectingErrorListener extends BaseErrorListener {
  final List<String> errors;

  _CollectingErrorListener(this.errors);

  @override
  void syntaxError(
    Recognizer<ATNSimulator> recognizer,
    Object? offendingSymbol,
    int? line,
    int charPositionInLine,
    String msg,
    RecognitionException? e,
  ) {
    errors.add('line ${line ?? '?'}:$charPositionInLine $msg');
  }
}
