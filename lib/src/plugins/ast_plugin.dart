import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import '../plugin.dart';

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
      return PluginResult.success(html, processingTime: stopwatch.elapsed);
    } catch (e) {
      stopwatch.stop();
      return PluginResult.error('AST parsing failed: $e');
    }
  }

  String _generateHtml(_AstNode root, List<dynamic> errors) {
    final buffer = StringBuffer();
    buffer.writeln('<div class="ast-view">');

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
    final indent = '  ' * depth;
    final hasChildren = node.children.isNotEmpty;
    final expandClass = hasChildren ? 'expandable' : 'leaf';
    final nodeClass = _getNodeClass(node.type);

    buffer.writeln('<div class="ast-node $expandClass $nodeClass" data-depth="$depth">');
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
  final List<_AstNode> children = [];

  _AstNode(this.type, {this.name, this.value, this.location});
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
    final n = _AstNode('ImportDirective',
        value: node.uri.stringValue, location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    final n = _AstNode('ExportDirective',
        value: node.uri.stringValue, location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitLibraryDirective(LibraryDirective node) {
    final n = _AstNode('LibraryDirective',
        name: node.name2?.name, location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final n = _AstNode('ClassDeclaration',
        name: node.name.lexeme, location: _loc(node));
    _push(n);

    if (node.extendsClause != null) {
      final ext = _AstNode('ExtendsClause',
          value: node.extendsClause!.superclass.name2.lexeme);
      _current.children.add(ext);
    }

    for (final member in node.members) {
      member.accept(this);
    }
    _pop();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final n = _AstNode('FunctionDeclaration',
        name: node.name.lexeme, location: _loc(node));
    _push(n);

    // Return type
    if (node.returnType != null) {
      final rt = _AstNode('ReturnType', value: node.returnType.toString());
      _current.children.add(rt);
    }

    // Parameters
    node.functionExpression.parameters?.accept(this);

    // Body
    node.functionExpression.body.accept(this);
    _pop();
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final n = _AstNode('MethodDeclaration',
        name: node.name.lexeme, location: _loc(node));
    _push(n);

    if (node.returnType != null) {
      final rt = _AstNode('ReturnType', value: node.returnType.toString());
      _current.children.add(rt);
    }

    node.parameters?.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name?.lexeme ?? '(default)';
    final n = _AstNode('ConstructorDeclaration', name: name, location: _loc(node));
    _push(n);
    node.parameters.accept(this);
    node.body?.accept(this);
    _pop();
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final variable in node.fields.variables) {
      final n = _AstNode('FieldDeclaration',
          name: variable.name.lexeme,
          value: node.fields.type?.toString(),
          location: _loc(node));
      _push(n);
      variable.initializer?.accept(this);
      _pop();
    }
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    final n = _AstNode('Parameters', location: _loc(node));
    _push(n);
    for (final param in node.parameters) {
      param.accept(this);
    }
    _pop();
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    final n = _AstNode('Parameter',
        name: node.name?.lexeme ?? '?',
        value: node.type?.toString(),
        location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitDefaultFormalParameter(DefaultFormalParameter node) {
    node.parameter.accept(this);
  }

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    final n = _AstNode('BlockBody', location: _loc(node));
    _push(n);
    node.block.accept(this);
    _pop();
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    final n = _AstNode('ExpressionBody', location: _loc(node));
    _push(n);
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
      final n = _AstNode('VariableDeclaration',
          name: variable.name.lexeme,
          value: node.variables.type?.toString() ?? 'var',
          location: _loc(node));
      _push(n);
      variable.initializer?.accept(this);
      _pop();
    }
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    final n = _AstNode('ExpressionStatement', location: _loc(node));
    _push(n);
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    final n = _AstNode('ReturnStatement', location: _loc(node));
    _push(n);
    node.expression?.accept(this);
    _pop();
  }

  @override
  void visitIfStatement(IfStatement node) {
    final n = _AstNode('IfStatement', location: _loc(node));
    _push(n);

    final cond = _AstNode('Condition');
    _push(cond);
    node.expression.accept(this);
    _pop();

    final then = _AstNode('Then');
    _push(then);
    node.thenStatement.accept(this);
    _pop();

    if (node.elseStatement != null) {
      final els = _AstNode('Else');
      _push(els);
      node.elseStatement!.accept(this);
      _pop();
    }

    _pop();
  }

  @override
  void visitForStatement(ForStatement node) {
    final n = _AstNode('ForStatement', location: _loc(node));
    _push(n);
    node.forLoopParts.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitForPartsWithDeclarations(ForPartsWithDeclarations node) {
    final init = _AstNode('Init');
    _push(init);
    for (final v in node.variables.variables) {
      final vn = _AstNode('Variable', name: v.name.lexeme);
      _push(vn);
      v.initializer?.accept(this);
      _pop();
    }
    _pop();

    if (node.condition != null) {
      final cond = _AstNode('Condition');
      _push(cond);
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
    final n = _AstNode('WhileStatement', location: _loc(node));
    _push(n);
    node.condition.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target != null ? '${node.target}.' : '';
    final n = _AstNode('MethodInvocation',
        name: '$target${node.methodName.name}', location: _loc(node));
    _push(n);
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final n = _AstNode('FunctionInvocation', location: _loc(node));
    _push(n);
    node.function.accept(this);
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final n = _AstNode('InstanceCreation',
        name: node.constructorName.toString(), location: _loc(node));
    _push(n);
    for (final arg in node.argumentList.arguments) {
      arg.accept(this);
    }
    _pop();
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final n = _AstNode('BinaryExpression',
        value: node.operator.lexeme, location: _loc(node));
    _push(n);
    node.leftOperand.accept(this);
    node.rightOperand.accept(this);
    _pop();
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    final n = _AstNode('PrefixExpression',
        value: node.operator.lexeme, location: _loc(node));
    _push(n);
    node.operand.accept(this);
    _pop();
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    final n = _AstNode('PostfixExpression',
        value: node.operator.lexeme, location: _loc(node));
    _push(n);
    node.operand.accept(this);
    _pop();
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final n = _AstNode('Assignment',
        value: node.operator.lexeme, location: _loc(node));
    _push(n);
    node.leftHandSide.accept(this);
    node.rightHandSide.accept(this);
    _pop();
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final n = _AstNode('Identifier', name: node.name, location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    final n = _AstNode('IntegerLiteral',
        value: node.value.toString(), location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    final n =
        _AstNode('DoubleLiteral', value: node.value.toString(), location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final n =
        _AstNode('StringLiteral', value: node.value, location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    final n = _AstNode('BooleanLiteral',
        value: node.value.toString(), location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitNullLiteral(NullLiteral node) {
    final n = _AstNode('NullLiteral', location: _loc(node));
    _current.children.add(n);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    final n = _AstNode('ListLiteral', location: _loc(node));
    _push(n);
    for (final element in node.elements) {
      element.accept(this);
    }
    _pop();
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    final type = node.isMap ? 'MapLiteral' : 'SetLiteral';
    final n = _AstNode(type, location: _loc(node));
    _push(n);
    for (final element in node.elements) {
      element.accept(this);
    }
    _pop();
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final n = _AstNode('ConditionalExpression', location: _loc(node));
    _push(n);
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
    final n = _AstNode('IndexExpression', location: _loc(node));
    _push(n);
    node.target?.accept(this);
    node.index.accept(this);
    _pop();
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final n = _AstNode('PropertyAccess',
        name: node.propertyName.name, location: _loc(node));
    _push(n);
    node.target?.accept(this);
    _pop();
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    final n = _AstNode('AwaitExpression', location: _loc(node));
    _push(n);
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    final n = _AstNode('ThrowExpression', location: _loc(node));
    _push(n);
    node.expression.accept(this);
    _pop();
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final n = _AstNode('FunctionExpression', location: _loc(node));
    _push(n);
    node.parameters?.accept(this);
    node.body.accept(this);
    _pop();
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final n = _AstNode('NamedArgument',
        name: node.name.label.name, location: _loc(node));
    _push(n);
    node.expression.accept(this);
    _pop();
  }
}
