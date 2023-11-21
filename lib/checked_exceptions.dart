import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:collection/collection.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:meta/meta_meta.dart';

PluginBase createPlugin() => _CheckedExceptionLinter();

class _CheckedExceptionLinter extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) =>
      const [_CheckedExceptionLintRule()];
}

class _CheckedExceptionLintRule extends DartLintRule {
  const _CheckedExceptionLintRule() : super(code: _code);

  static const _code = LintCode(
    name: "handle_declared_exceptions",
    problemMessage:
        "The call could generate an unhandled exception of type {0}.\n{1}",
    correctionMessage:
        "Catch every declared exception or delegate the handling by adding one or multiple @Throws annotations with the delegated exception types.",
    errorSeverity: ErrorSeverity.WARNING,
  );

  static const _checker = TypeChecker.fromUrl(
    "package:checked_exceptions/checked_exceptions.dart#Throws",
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addConstructorName((node) {
      final Element? cls = node.type.element;

      if (cls == null) return;
      if (cls is! ClassElement) return;

      final ConstructorElement? constructor = cls.constructors.firstWhereOrNull(
        (e) => node.name == null ? e.name.isEmpty : node.name!.name == e.name,
      );

      if (constructor == null) return;

      return _handleNode(node, node, constructor, reporter);
    });

    context.registry.addMethodInvocation(
      (node) => _handleInvocation(node, reporter),
    );

    context.registry.addFunctionExpressionInvocation(
      (node) => _handleInvocation(node, reporter),
    );
  }

  void _handleInvocation(InvocationExpression node, ErrorReporter reporter) {
    final AstNode nameNode;
    final Element? target;

    if (node is MethodInvocation) {
      target = node.methodName.staticElement;
      nameNode = node.methodName;
    } else if (node is FunctionExpressionInvocation) {
      target = node.staticElement;
      nameNode = node;
    } else {
      return;
    }
    return _handleNode(node, nameNode, target, reporter);
  }

  void _handleNode(
    AstNode node,
    AstNode nameNode,
    Element? target,
    ErrorReporter reporter,
  ) {
    if (target == null) return;

    final ExecutableElement? annotatedElement =
        _checker.hasAnnotationOfExact(target, throwOnUnresolved: false)
            ? target as ExecutableElement
            : null;

    if (annotatedElement == null) return;

    final _CheckedTypeList checkedTypes = _getCheckedTypes(annotatedElement);
    final List<MapEntry<String, String?>> exceptionsToCatch = checkedTypes
        .map((e) => MapEntry(e.key.element!.displayName, e.value))
        .toList();

    final TryStatement? tryBlock = _checkIfWrappedInNode<TryStatement>(node);

    final FunctionDeclaration? funDeclaration =
        _checkIfWrappedInNode<FunctionDeclaration>(node);
    final MethodDeclaration? methodDeclaration =
        _checkIfWrappedInNode<MethodDeclaration>(node);
    final List<DartType> delegatedTypes =
        _checkDelegatedExceptions(funDeclaration, methodDeclaration)
            .map((e) => e.key)
            .toList();

    exceptionsToCatch.removeWhere(
      (a) => delegatedTypes.any((b) => b.element!.displayName == a.key),
    );

    if (tryBlock == null) {
      if (exceptionsToCatch.isNotEmpty) {
        reporter.reportErrorForNode(
          _code,
          nameNode,
          [
            exceptionsToCatch.map((e) => e.key).formattedForLint,
            exceptionsToCatch.formattedForExceptionListWithMessage,
          ],
        );
      }
      return;
    }

    final bool hasACatchAll =
        tryBlock.catchClauses.any((e) => e.exceptionType == null);

    if (hasACatchAll) return;

    final List<CatchClause> catchedTypes =
        tryBlock.catchClauses.where((e) => e.exceptionType != null).toList();

    final List<TypeAnnotation> catchedExceptions = catchedTypes
        .where(
          (a) => checkedTypes.any(
            (b) {
              final checker = TypeChecker.fromStatic(b.key);
              return checker.isAssignableFromType(a.exceptionType!.type!) ||
                  checker.isSuperTypeOf(a.exceptionType!.type!);
            },
          ),
        )
        .map((e) => e.exceptionType!)
        .toList();

    exceptionsToCatch.removeWhere(
      (a) =>
          catchedExceptions.any((b) => b.type!.element!.displayName == a.key),
    );

    if (exceptionsToCatch.isNotEmpty) {
      reporter.reportErrorForNode(
        _code,
        nameNode,
        [
          exceptionsToCatch.map((e) => e.key).formattedForLint,
          exceptionsToCatch.formattedForExceptionListWithMessage,
        ],
      );
    }
  }
}

typedef _CheckedTypeList = List<_CheckedType>;
typedef _CheckedType = MapEntry<DartType, String?>;

_CheckedTypeList _checkDelegatedExceptions(
  FunctionDeclaration? funDeclaration,
  MethodDeclaration? methodDeclaration,
) {
  if (funDeclaration != null) {
    return _getCheckedTypes(funDeclaration.declaredElement!);
  }

  if (methodDeclaration != null) {
    return _getCheckedTypes(methodDeclaration.declaredElement!);
  }

  return [];
}

_CheckedTypeList _getCheckedTypes(Element element) {
  final List<DartObject> annotations = _CheckedExceptionLintRule._checker
      .annotationsOfExact(element, throwOnUnresolved: false)
      .toList();

  final _CheckedTypeList checkedTypes = [];

  for (final DartObject annotation in annotations) {
    final DartType? exception = annotation.getField('exception')?.toTypeValue();
    final String? message = annotation.getField('message')?.toStringValue();

    if (exception == null) continue;
    if (exception.element is! ClassElement) continue;

    checkedTypes.add(MapEntry(exception, message));
  }

  return checkedTypes;
}

extension on Iterable<String> {
  String get formattedForLint {
    if (isEmpty) return "Exception";
    if (length == 1) return single;

    final String commaPart = toList().sublist(0, length - 1).join(", ");

    return [commaPart, last].join(" or ");
  }
}

extension on List<MapEntry<String, String?>> {
  String get formattedForExceptionListWithMessage {
    final Iterable<MapEntry<String, String>> ref =
        where((e) => e.value != null).cast<MapEntry<String, String>>();

    if (ref.isEmpty) return "";

    final String entries = where((e) => e.value != null)
        .map((e) => "[${e.key}]: ${e.value}.")
        .join("\n");

    return "$entries\n";
  }
}

T? _checkIfWrappedInNode<T extends AstNode>(AstNode base) {
  final AstNode? parent = base.parent;
  if (parent == null || parent == base.root) return null;

  if (parent is T) return parent;

  return _checkIfWrappedInNode<T>(parent);
}

/// An annotation that tells the user that the method they are calling could
/// throw [exception] and they need to handle the eventuality.
///
/// To do so, you can wrap the call in a try/catch block and catch the specific exception
/// with `on` or catch everything with `catch(e)`, or either delegate the handling to the
/// caller of the method by marking said method with a @Throws annotation with the same [exception]
/// as the one not being handled.
///
/// The optional [message] parameter tells the user when the exception could happen, hinting on how to avoid it
/// potentially.
@Target({
  TargetKind.method,
  TargetKind.function,
})
class Throws {
  final Type exception;
  final String? message;

  const Throws([this.exception = Exception, this.message]);
}
