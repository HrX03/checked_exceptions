import 'dart:collection';

import 'package:analyzer/dart/element/element.dart';

typedef Matcher = bool Function(ExecutableElement element);

ExecutableElement? findOverriddenMemberWithExpectedMatch(
  Element element,
  Matcher matcher,
) {
  //Element member = node.declaredElement;
  if (element.enclosingElement is! InterfaceElement) {
    return null;
  }
  final classElement = element.enclosingElement! as InterfaceElement;
  final name = element.name;
  if (name == null) return null;

  // Walk up the type hierarchy from [classElement], ignoring direct
  // interfaces.
  final superclasses = Queue<InterfaceElement?>();

  void addToQueue(InterfaceElement element) {
    superclasses.addAll(element.mixins.map((i) => i.element));
    superclasses.add(element.supertype?.element);
    if (element is MixinElement) {
      superclasses.addAll(element.superclassConstraints.map((i) => i.element));
    }
  }

  final visitedClasses = <InterfaceElement>{};
  addToQueue(classElement);
  while (superclasses.isNotEmpty) {
    final ancestor = superclasses.removeFirst();
    if (ancestor == null || !visitedClasses.add(ancestor)) {
      continue;
    }
    final member = ancestor.getMethod(name) ??
        ancestor.getGetter(name) ??
        ancestor.getSetter(name);
    if (member is MethodElement && matcher(member)) {
      return member;
    }
    if (member is PropertyAccessorElement && matcher(member)) {
      return member;
    }
    addToQueue(ancestor);
  }
  return null;
}
