import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import '../plugin.dart';

// Analyzer version - update when upgrading the analyzer package
const _analyzerVersion = '6.4.1';

/// Plugin that displays the token stream from lexical analysis
class TokenStreamPlugin extends Plugin {
  @override
  String get id => 'token_stream';

  @override
  String get name => 'Token Stream';

  @override
  String get icon => '🔤';

  @override
  Future<PluginResult> process(String sourceCode, PluginContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Parse to get the token stream
      final result = parseString(content: sourceCode, throwIfDiagnostics: false);
      final tokens = <_TokenInfo>[];

      // Walk through all tokens
      Token? token = result.unit.beginToken;
      while (token != null && token.type != TokenType.EOF) {
        tokens.add(_TokenInfo(
          type: token.type.toString(),
          lexeme: token.lexeme,
          offset: token.offset,
          length: token.length,
          line: _getLine(sourceCode, token.offset),
          column: _getColumn(sourceCode, token.offset),
        ));

        // Also capture any preceding comments
        Token? comment = token.precedingComments;
        while (comment != null) {
          tokens.insert(tokens.length - 1, _TokenInfo(
            type: 'COMMENT',
            lexeme: comment.lexeme,
            offset: comment.offset,
            length: comment.length,
            line: _getLine(sourceCode, comment.offset),
            column: _getColumn(sourceCode, comment.offset),
            isComment: true,
          ));
          comment = comment.next;
        }

        token = token.next;
      }

      // Sort by offset
      tokens.sort((a, b) => a.offset.compareTo(b.offset));

      stopwatch.stop();

      // Generate HTML output
      final html = _generateHtml(tokens);
      return PluginResult.success(html, processingTime: stopwatch.elapsed);
    } catch (e) {
      stopwatch.stop();
      return PluginResult.error('Tokenization failed: $e');
    }
  }

  int _getLine(String source, int offset) {
    int line = 1;
    for (int i = 0; i < offset && i < source.length; i++) {
      if (source[i] == '\n') line++;
    }
    return line;
  }

  int _getColumn(String source, int offset) {
    int column = 1;
    for (int i = offset - 1; i >= 0 && source[i] != '\n'; i--) {
      column++;
    }
    return column;
  }

  String _generateHtml(List<_TokenInfo> tokens) {
    final buffer = StringBuffer();
    buffer.writeln('<div class="token-stream">');
    buffer.writeln('<div class="plugin-header">');
    buffer.writeln('<span class="plugin-badge">Analyzer</span>');
    buffer.writeln('<span class="version-info">v$_analyzerVersion</span>');
    buffer.writeln('</div>');
    buffer.writeln('<table class="token-table">');
    buffer.writeln('<thead><tr>');
    buffer.writeln('<th>Line</th><th>Col</th><th>Type</th><th>Lexeme</th>');
    buffer.writeln('</tr></thead>');
    buffer.writeln('<tbody>');

    for (final token in tokens) {
      final cssClass = _getCssClass(token);
      final escapedLexeme = _escapeHtml(token.lexeme);
      buffer.writeln('<tr class="$cssClass" data-offset="${token.offset}" data-length="${token.length}">');
      buffer.writeln('<td class="line-num">${token.line}</td>');
      buffer.writeln('<td class="col-num">${token.column}</td>');
      buffer.writeln('<td class="token-type">${token.type}</td>');
      buffer.writeln('<td class="token-lexeme"><code>$escapedLexeme</code></td>');
      buffer.writeln('</tr>');
    }

    buffer.writeln('</tbody></table>');
    buffer.writeln('<div class="token-count">Total: ${tokens.length} tokens</div>');
    buffer.writeln('</div>');
    return buffer.toString();
  }

  String _getCssClass(_TokenInfo token) {
    if (token.isComment) return 'token-comment';
    final type = token.type.toLowerCase();
    if (type.contains('keyword')) return 'token-keyword';
    if (type.contains('string')) return 'token-string';
    if (type.contains('int') || type.contains('double')) return 'token-number';
    if (type.contains('identifier')) return 'token-identifier';
    return 'token-default';
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
  final String lexeme;
  final int offset;
  final int length;
  final int line;
  final int column;
  final bool isComment;

  _TokenInfo({
    required this.type,
    required this.lexeme,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    this.isComment = false,
  });
}
