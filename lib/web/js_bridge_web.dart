import 'dart:convert';
import 'dart:js_util' as js_util;
import 'package:js/js.dart';

@JS('detectFaceFromImage')
external Object _detectFaceFromImage(String base64Image);

Future<Map<String, dynamic>> detectFaceWeb(String base64) async {
  final result = await js_util.promiseToFuture(_detectFaceFromImage(base64));

  return jsonDecode(result as String);
}
