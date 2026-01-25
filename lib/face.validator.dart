import 'package:flutter/services.dart';

class FaceValidator {
  // 🔁 UPDATE HERE if you change channel name in Android
  static const MethodChannel _channel = MethodChannel('com.example.face_detection/face_validator');

  /// Call native Android ML Kit to analyze face
  static Future<Map<String, dynamic>> analyzeFace(String imagePath) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('analyzeFace', {
        // 🔁 Image file path from camera/gallery
        'path': imagePath,
      });

      if (result == null) {
        return {};
      }

      // Convert Map<dynamic, dynamic> → Map<String, dynamic>
      return result.map((key, value) => MapEntry(key.toString(), value));
    } on PlatformException catch (e) {
      throw Exception('Face detection failed: ${e.code} - ${e.message}');
    }
  }
}
