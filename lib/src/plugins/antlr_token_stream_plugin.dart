import 'package:antlr4/antlr4.dart';
import '../antlr/DartLexer.dart';
import '../plugin.dart';

/// Plugin that displays the ANTLR token stream from lexical analysis
class AntlrTokenStreamPlugin extends Plugin {
  @override
  String get id => 'antlr_token_stream';

  @override
  String get name => 'ANTLR Tokens';

  @override
  String get icon => '🔠';

  @override
  Future<PluginResult> process(String sourceCode, PluginContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      final input = InputStream.fromString(sourceCode);
      final lexer = DartLexer(input);

      // Collect all tokens
      final tokens = <_TokenInfo>[];
      Token token;

      do {
        token = lexer.nextToken();
        if (token.type != Token.EOF) {
          tokens.add(_TokenInfo(
            type: _getTokenName(lexer, token.type),
            typeIndex: token.type,
            lexeme: token.text ?? '',
            line: token.line ?? 0,
            column: token.charPositionInLine,
            startIndex: token.startIndex,
            stopIndex: token.stopIndex,
            channel: token.channel,
          ));
        }
      } while (token.type != Token.EOF);

      stopwatch.stop();

      final html = _generateHtml(tokens);
      return PluginResult.success(html, processingTime: stopwatch.elapsed);
    } catch (e, stack) {
      stopwatch.stop();
      return PluginResult.error('ANTLR Tokenization failed: $e\n$stack');
    }
  }

  String _getTokenName(DartLexer lexer, int tokenType) {
    if (tokenType < 0) return 'EOF';
    final vocabulary = lexer.vocabulary;
    final symbolicName = vocabulary.getSymbolicName(tokenType);
    if (symbolicName != null && symbolicName.isNotEmpty) {
      return symbolicName;
    }
    final literalName = vocabulary.getLiteralName(tokenType);
    if (literalName != null && literalName.isNotEmpty) {
      return literalName;
    }
    return 'T__${tokenType}';
  }

  String _generateHtml(List<_TokenInfo> tokens) {
    final buffer = StringBuffer();
    buffer.writeln('<div class="token-stream antlr-tokens">');
    buffer.writeln('<div class="plugin-header">');
    buffer.writeln('<span class="plugin-badge">ANTLR4</span>');
    buffer.writeln('<span class="grammar-info">Dart.g4 v0.58 (Official Dart SDK)</span>');
    buffer.writeln('</div>');
    buffer.writeln('<table class="token-table">');
    buffer.writeln('<thead><tr>');
    buffer.writeln('<th>Line</th><th>Col</th><th>Type</th><th>Lexeme</th><th>Channel</th>');
    buffer.writeln('</tr></thead>');
    buffer.writeln('<tbody>');

    for (final token in tokens) {
      final cssClass = _getCssClass(token);
      final escapedLexeme = _escapeHtml(token.lexeme);
      final channelName = token.channel == 0 ? 'DEFAULT' : 'HIDDEN';
      final length = token.stopIndex - token.startIndex + 1;
      buffer.writeln('<tr class="$cssClass" data-offset="${token.startIndex}" data-length="$length">');
      buffer.writeln('<td class="line-num">${token.line}</td>');
      buffer.writeln('<td class="col-num">${token.column}</td>');
      buffer.writeln('<td class="token-type">${token.type}</td>');
      buffer.writeln('<td class="token-lexeme"><code>$escapedLexeme</code></td>');
      buffer.writeln('<td class="token-channel">$channelName</td>');
      buffer.writeln('</tr>');
    }

    buffer.writeln('</tbody></table>');
    buffer.writeln('<div class="token-count">Total: ${tokens.length} tokens</div>');
    buffer.writeln('</div>');
    return buffer.toString();
  }

  String _getCssClass(_TokenInfo token) {
    final type = token.type.toUpperCase();
    if (type.contains('COMMENT')) return 'token-comment';
    if (type.contains('STRING')) return 'token-string';
    if (type == 'NUMBER' || type == 'HEX_NUMBER') return 'token-number';
    if (type == 'IDENTIFIER') return 'token-identifier';
    if (type.contains('WS') || type == 'FEFF') return 'token-whitespace';
    // Check for keywords
    if (_isKeyword(type)) return 'token-keyword';
    return 'token-default';
  }

  bool _isKeyword(String type) {
    const keywords = {
      'ASSERT', 'BREAK', 'CASE', 'CATCH', 'CLASS', 'CONST', 'CONTINUE',
      'DEFAULT', 'DO', 'ELSE', 'ENUM', 'EXTENDS', 'FALSE', 'FINAL',
      'FINALLY', 'FOR', 'IF', 'IN', 'IS', 'NEW', 'NULL', 'RETHROW',
      'RETURN', 'SUPER', 'SWITCH', 'THIS', 'THROW', 'TRUE', 'TRY',
      'VAR', 'VOID', 'WHILE', 'WITH', 'ABSTRACT', 'AS', 'AUGMENT',
      'COVARIANT', 'DEFERRED', 'DYNAMIC', 'EXPORT', 'EXTENSION',
      'EXTERNAL', 'FACTORY', 'FUNCTION', 'GET', 'IMPLEMENTS', 'IMPORT',
      'INTERFACE', 'LATE', 'LIBRARY', 'OPERATOR', 'MIXIN', 'PART',
      'REQUIRED', 'SET', 'STATIC', 'TYPEDEF', 'AWAIT', 'YIELD', 'ASYNC',
      'BASE', 'HIDE', 'OF', 'ON', 'SEALED', 'SHOW', 'SYNC', 'TYPE', 'WHEN',
    };
    return keywords.contains(type);
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll('\n', '↵')
        .replaceAll('\t', '→')
        .replaceAll(' ', '·');
  }
}

class _TokenInfo {
  final String type;
  final int typeIndex;
  final String lexeme;
  final int line;
  final int column;
  final int startIndex;
  final int stopIndex;
  final int channel;

  _TokenInfo({
    required this.type,
    required this.typeIndex,
    required this.lexeme,
    required this.line,
    required this.column,
    required this.startIndex,
    required this.stopIndex,
    required this.channel,
  });
}
