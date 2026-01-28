import 'dart:convert';
import 'dart:js_util' as js_util;
import 'package:js/js.dart';

@JS('detectFaceFromImage')
external Object _detectFaceFromImage(String base64Image);

Future<Map<String, dynamic>> detectFaceWeb(String base64) async {
  // Convert JS Promise → Dart Future
  final jsResult = await js_util.promiseToFuture(_detectFaceFromImage(base64));

  // Ensure it's String before decoding
  final jsonString = jsResult as String;
  return jsonDecode(jsonString);
}
