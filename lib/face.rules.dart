import 'package:face_detection/enum.dart';

class FaceRules {
  static String? validate(Map<String, dynamic> data, {required FaceType expectedFace, required bool isFrontCamera}) {
    // 1️⃣ Face count - handle both int and double from native code
    final faceCount = ((data['faceCount'] ?? 0) as num).toInt();
    if (faceCount == 0) return 'No face detected';
    if (faceCount > 1) return 'Multiple faces detected';

    // 2️⃣ Check if full face is visible (nose and mouth landmarks present)
    final isFullFace = data['isFullFace'] as bool? ?? false;
    if (!isFullFace) return 'Please position your entire face in the frame';

    // 3️⃣ Head pose (YAW) - handle both int and double from native code
    double yaw = ((data['yaw'] ?? 0) as num).toDouble();

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

    // 4️⃣ Eyes visibility - handle both int and double from native code
    final leftEye = ((data['leftEyeOpen'] ?? 1.0) as num).toDouble();
    final rightEye = ((data['rightEyeOpen'] ?? 1.0) as num).toDouble();
    if (leftEye < 0.5 || rightEye < 0.5) {
      return 'Please make sure your eyes are visible';
    }

    return null; // ✅ VALID
  }
}
