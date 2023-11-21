import 'dart:convert';

import 'package:checked_exceptions/checked_exceptions.dart';

void main(List<String> args) {
  final dynamic result;

  // change the type of the catch or remove the try/catch to see lint
  try {
    result = decodeJson('{"a: 0}');
  } on FormatException {
    print("fail :(");
    return;
  }

  print(result);
}

@Throws(FormatException, "[source] is not valid json")
dynamic decodeJson(String source) => jsonDecode(source);

@Throws(FormatException)
@Throws(ArgumentError, "When [number] is negative")
void method(int number) {}

const throwsInvalidJson = Throws(FormatException, "[source] is not valid json");
