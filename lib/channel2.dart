// import 'dart:typed_data';

// import 'package:camera/camera.dart';
// import 'package:flutter/services.dart';

// class Channel {
//   static const MethodChannel _channel = MethodChannel('com.example.face_detection/face_validator');

//   /// Analyze face from a saved file path (used for final still capture)
//   static Future<Map<String, dynamic>> analyzeFace(String imagePath) async {
//     try {
//       final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('analyzeFace', {'path': imagePath});
//       if (result == null) return {};
//       return result.map((k, v) => MapEntry(k.toString(), v));
//     } on PlatformException catch (e) {
//       throw Exception('Face detection failed: ${e.code} - ${e.message}');
//     }
//   }

//   /// Analyze face from a live CameraImage stream frame.
//   ///
//   /// Sends raw YUV/BGRA plane bytes + metadata directly to native.
//   /// Native builds VisionImage from pixel data — no file I/O at all.
//   static Future<Map<String, dynamic>> analyzeFromStream(
//     CameraImage image, {
//     required bool isFront,
//     required int sensorOrientation,
//   }) async {
//     try {
//       final List<Uint8List> planeBytes = image.planes.map((p) => p.bytes).toList();
//       final List<int> bytesPerRow = image.planes.map((p) => p.bytesPerRow).toList();
//       final List<int> bytesPerPixel = image.planes.map((p) => p.bytesPerPixel ?? 1).toList();

//       final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('analyzeFromStream', {
//         'planes': planeBytes,
//         'bytesPerRow': bytesPerRow,
//         'bytesPerPixel': bytesPerPixel,
//         'width': image.width,
//         'height': image.height,
//         'format': image.format.raw,
//         'isFront': isFront,
//         'sensorOrientation': sensorOrientation,
//       });
//       if (result == null) return {};
//       return result.map((k, v) => MapEntry(k.toString(), v));
//     } on PlatformException catch (e) {
//       throw Exception('Stream face detection failed: ${e.code} - ${e.message}');
//     }
//   }
// }
