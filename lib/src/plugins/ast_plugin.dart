import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import '../plugin.dart';

// Analyzer version - update when upgrading the analyzer package
const _analyzerVersion = '6.4.1';

/// Plugin that displays the Abstract Syntax Tree
class AstPlugin extends Plugin {
  @override
  String get id => 'ast';

  @override
  String get name => 'AST';

  @override
  String get icon => '🌳';

  @override
  Future<PluginResult> process(String sourceCode, PluginContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = parseString(content: sourceCode, throwIfDiagnostics: false);
      final unit = result.unit;

      // Build AST representation
      final visitor = _AstTreeBuilder();
      unit.accept(visitor);

      stopwatch.stop();

      final html = _generateHtml(visitor.root, result.errors);
      return PluginResult.success(html, processingTime: stopwatch.elapsed, hasIssues: result.errors.isNotEmpty);
    } catch (e) {
      stopwatch.stop();
      return PluginResult.error('AST parsing failed: $e');
    }
  }

  String _generateHtml(_AstNode root, List<dynamic> errors) {
    final buffer = StringBuffer();
    buffer.writeln('<div class="ast-view">');

    buffer.writeln('<div class="plugin-header">');
    buffer.writeln('<span class="plugin-badge">Analyzer</span>');
    buffer.writeln('<span class="version-info">v$_analyzerVersion</span>');
    buffer.writeln('</div>');

    // Show errors if any
    if (errors.isNotEmpty) {
      buffer.writeln('<div class="ast-errors">');
      buffer.writeln('<h4>Parse Errors (${errors.length})</h4>');
      buffer.writeln('<ul>');
      for (final error in errors) {
        buffer.writeln('<li class="error-item">${_escapeHtml(error.toString())}</li>');
      }
      buffer.writeln('</ul></div>');
    }

    // Show AST tree
    buffer.writeln('<div class="ast-tree">');
    _writeNode(buffer, root, 0);
    buffer.writeln('</div>');

    buffer.writeln('</div>');
    return buffer.toString();
  }

  void _writeNode(StringBuffer buffer, _AstNode node, int depth) {
    final hasChildren = node.children.isNotEmpty;
    final expandClass = hasChildren ? 'expandable' : 'leaf';
    final nodeClass = _getNodeClass(node.type);

    final dataAttrs = node.offset != null && node.length != null
        ? 'data-offset="${node.offset}" data-length="${node.length}"'
        : '';

    buffer.writeln('<div class="ast-node $expandClass $nodeClass" data-depth="$depth" $dataAttrs>');
    buffer.writeln('<span class="node-toggle">${hasChildren ? "▶" : "○"}</span>');
    buffer.writeln('<span class="node-type">${_escapeHtml(node.type)}</span>');

    if (node.name != null) {
      buffer.writeln('<span class="node-name">${_escapeHtml(node.name!)}</span>');
    }

    if (node.value != null) {
      buffer.writeln('<span class="node-value">${_escapeHtml(node.value!)}</span>');
    }

    if (node.location != null) {
      buffer.writeln('<span class="node-location">${node.location}</span>');
    }

    if (hasChildren) {
      buffer.writeln('<div class="node-children collapsed">');
      for (final child in node.children) {
        _writeNode(buffer, child, depth + 1);
      }
      buffer.writeln('</div>');
    }

    buffer.writeln('</div>');
  }

  String _getNodeClass(String type) {
    if (type.contains('Declaration')) return 'node-declaration';
    if (type.contains('Statement')) return 'node-statement';
    if (type.contains('Expression')) return 'node-expression';
    if (type.contains('Literal')) return 'node-literal';
    if (type.contains('Identifier')) return 'node-identifier';
    if (type.contains('Type')) return 'node-type';
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

class _AstNode {
  final String type;
  final String? name;
  final String? value;
  final String? location;
  final int? offset;
  final int? length;
  final List<_AstNode> children = [];

  _AstNode(this.type, {this.name, this.value, this.location, this.offset, this.length});
}

class _AstTreeBuilder extends GeneralizingAstVisitor<void> {
  final _AstNode root = _AstNode('CompilationUnit');
  final List<_AstNode> _stack = [];

  _AstTreeBuilder() {
    _stack.add(root);
  }

  _AstNode get _current => _stack.last;

  void _push(_AstNode node) {
    _current.children.add(node);
    _stack.add(node);
  }

  void _pop() {
    if (_stack.length > 1) _stack.removeLast();
  }

  String _loc(AstNode node) {
    return '[${node.offset}:${node.offset + node.length}]';
  }

  _AstNode _node(String type, AstNode astNode, {String? name, String? value}) {
    return _AstNode(type,
        name: name,
        value: value,
        location: _loc(astNode),
        offset: astNode.offset,
        length: astNode.length);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    root.children.clear();
    for (final directive in node.directives) {
      directive.accept(this);
    }
    for (final declaration in node.declarations) {
      declaration.accept(this);
    }
  }

  @override
  void visitImportDirective(ImportDirective node) {
    _current.children.add(_node('ImportDirective', node, value: node.uri.stringValue));
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _current.children.add(_node('ExportDirective', node, value: node.uri.stringValue));
  }

  @override
  void visitLibraryDirective(LibraryDirective node) {
    _current.children.add(_node('LibraryDirective', node, name: node.name2?.name));
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _push(_node('ClassDeclaration', node, name: node.name.lexeme));

    if (node.extendsClause != null) {
      _current.children.add(_node('ExtendsClause', node.extendsClause!,
          value: node.extendsClause!.superclass.name2.lexeme));
    }

    for (final member in node.members) {
      member.accept(this);
    }
    _pop();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _push(_node('FunctionDeclaration', node, name: node.name.lexeme));

    // Return type
    if (node.returnType != null) {
      _current.children.add(_node('ReturnType', node.returnType!, value: node.returnType.toString()));
    }

    // Parameters
    node.functionExpression.parameters?.accept(this);

    // Body
    node.functionExpression.body.accept(this);
    _pop();
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _push(_node('MethodDeclaration', node, name: node.name.lexeme));

    if (node.returnType != null) {
      _current.children.add(_node('ReturnType', node.returnType!, value: node.returnType.toString()));
    }

    node.parameters?.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name?.lexeme ?? '(default)';
    _push(_node('ConstructorDeclaration', node, name: name));
    node.parameters.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final variable in node.fields.variables) {
      _push(_node('FieldDeclaration', node,
          name: variable.name.lexeme,
          value: node.fields.type?.toString()));
      variable.initializer?.accept(this);
      _pop();
    }
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    _push(_node('Parameters', node));
    for (final param in node.parameters) {
      param.accept(this);
    }
    _pop();
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    _current.children.add(_node('Parameter', node,
        name: node.name?.lexeme ?? '?',
        value: node.type?.toString()));
  }

  @override
  void visitDefaultFormalParameter(DefaultFormalParameter node) {
    node.parameter.accept(this);
  }

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    _push(_node('BlockBody', node));
    node.block.accept(this);
    _pop();
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    _push(_node('ExpressionBody', node));
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitBlock(Block node) {
    for (final statement in node.statements) {
      statement.accept(this);
    }
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    for (final variable in node.variables.variables) {
      _push(_node('VariableDeclaration', node,
          name: variable.name.lexeme,
          value: node.variables.type?.toString() ?? 'var'));
      variable.initializer?.accept(this);
      _pop();
    }
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    _push(_node('ExpressionStatement', node));
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    _push(_node('ReturnStatement', node));
    node.expression?.accept(this);
    _pop();
  }

  @override
  void visitIfStatement(IfStatement node) {
    _push(_node('IfStatement', node));

    _push(_node('Condition', node.expression));
    node.expression.accept(this);
    _pop();

    _push(_node('Then', node.thenStatement));
    node.thenStatement.accept(this);
    _pop();

    if (node.elseStatement != null) {
      _push(_node('Else', node.elseStatement!));
      node.elseStatement!.accept(this);
      _pop();
    }

    _pop();
  }

  @override
  void visitForStatement(ForStatement node) {
    _push(_node('ForStatement', node));
    node.forLoopParts.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitForPartsWithDeclarations(ForPartsWithDeclarations node) {
    _push(_node('Init', node.variables));
    for (final v in node.variables.variables) {
      _push(_node('Variable', v, name: v.name.lexeme));
      v.initializer?.accept(this);
      _pop();
    }
    _pop();

    if (node.condition != null) {
      _push(_node('Condition', node.condition!));
      node.condition!.accept(this);
      _pop();
    }

    final upd = _AstNode('Update');
    _push(upd);
    for (final u in node.updaters) {
      u.accept(this);
    }
    _pop();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _push(_node('WhileStatement', node));
    node.condition.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target != null ? '${node.target}.' : '';
    _push(_node('MethodInvocation', node, name: '$target${node.methodName.name}'));
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _push(_node('FunctionInvocation', node));
    node.function.accept(this);
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _push(_node('InstanceCreation', node, name: node.constructorName.toString()));
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _push(_node('BinaryExpression', node, value: node.operator.lexeme));
    node.leftOperand.accept(this);
    node.rightOperand.accept(this);
    _pop();
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _push(_node('PrefixExpression', node, value: node.operator.lexeme));
    node.operand.accept(this);
    _pop();
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _push(_node('PostfixExpression', node, value: node.operator.lexeme));
    node.operand.accept(this);
    _pop();
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _push(_node('Assignment', node, value: node.operator.lexeme));
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
    _pop();
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _current.children.add(_node('Identifier', node, name: node.name));
  }

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    _current.children.add(_node('IntegerLiteral', node, value: node.value.toString()));
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    _current.children.add(_node('DoubleLiteral', node, value: node.value.toString()));
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _current.children.add(_node('StringLiteral', node, value: node.value));
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    _current.children.add(_node('BooleanLiteral', node, value: node.value.toString()));
  }

  @override
  void visitNullLiteral(NullLiteral node) {
    _current.children.add(_node('NullLiteral', node));
  }

  @override
  void visitListLiteral(ListLiteral node) {
    _push(_node('ListLiteral', node));
    for (final element in node.elements) {
      element.accept(this);
    }
    _pop();
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    final type = node.isMap ? 'MapLiteral' : 'SetLiteral';
    _push(_node(type, node));
    for (final element in node.elements) {
      element.accept(this);
    }
    _pop();
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _push(_node('ConditionalExpression', node));
    node.condition.accept(this);
    node.thenExpression.accept(this);
    node.elseExpression.accept(this);
    _pop();
  }

  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    node.expression.accept(this);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    _push(_node('IndexExpression', node));
    node.target?.accept(this);
    node.index.accept(this);
    _pop();
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _push(_node('PropertyAccess', node, name: node.propertyName.name));
    node.target?.accept(this);
    _pop();
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    _push(_node('AwaitExpression', node));
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    _push(_node('ThrowExpression', node));
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _push(_node('FunctionExpression', node));
    node.parameters?.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    _push(_node('NamedArgument', node, name: node.name.label.name));
    node.expression.accept(this);
    _pop();
  }
}
