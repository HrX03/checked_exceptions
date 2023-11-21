import 'dart:convert';

import 'package:checked_exceptions/checked_exceptions.dart';

void main(List<String> args) {
  final dynamic result;

  try {
    result = decodeJson('{"a: 0}');
  } on int {
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
