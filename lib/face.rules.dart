import 'package:face_detection/enum.dart';

class FaceRules {
  static String? validate(Map<String, dynamic> data, {required FaceType expectedFace, required bool isFrontCamera}) {
    // 1️⃣ Face count
    final faceCount = (data['faceCount'] ?? 0) as int;
    if (faceCount == 0) return 'No face detected';
    if (faceCount > 1) return 'Multiple faces detected';

    // 2️⃣ Head pose (YAW)
    double yaw = (data['yaw'] ?? 0).toDouble();

    if (isFrontCamera) {
      yaw = -yaw;
    }

    switch (expectedFace) {
      case FaceType.front:
        if (yaw.abs() > 15) {
          return 'Please look straight at the camera';
        }
        break;

      case FaceType.left:
        // Left face capture → user must turn RIGHT
        if (yaw < 20) {
          return 'Please turn your face to the RIGHT';
        }
        break;

      case FaceType.right:
        // Right face capture → user must turn LEFT
        if (yaw > -20) {
          return 'Please turn your face to the LEFT';
        }
        break;
    }

    // 3️⃣ Eyes visibility
    final leftEye = (data['leftEyeOpen'] ?? 1.0).toDouble();
    final rightEye = (data['rightEyeOpen'] ?? 1.0).toDouble();
    if (leftEye < 0.2 || rightEye < 0.2) {
      return 'Please make sure your eyes are visible';
    }

    return null; // ✅ VALID
  }
}
