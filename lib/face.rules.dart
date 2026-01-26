import 'dart:developer';

class FaceRules {
  static String? validate(Map<String, dynamic> data) {
    print('FaceRules.validate: $data');

    // 1️⃣ Face count
    final faceCount = (data['faceCount'] ?? 0) as int;
    if (faceCount == 0) return 'No face detected';
    if (faceCount > 1) return 'Multiple faces detected';

    // 2️⃣ Head pose
    final yaw = (data['yaw'] ?? 0).toDouble();
    if (yaw.abs() > 15) {
      return 'Please look straight at the camera';
    }

    // 3️⃣ Eyes visibility (REAL signal)
    final leftEye = (data['leftEyeOpen'] ?? 1.0).toDouble();
    final rightEye = (data['rightEyeOpen'] ?? 1.0).toDouble();
    if (leftEye < 0.2 || rightEye < 0.2) {
      return 'Please make sure your eyes are visible';
    }

    // 4️⃣ Mouth / mask detection (STATISTICAL → manual check)
    final upperLip = (data['upperLipPoints'] as List?)?.cast<List<dynamic>>() ?? [];
    final lowerLip = (data['lowerLipPoints'] as List?)?.cast<List<dynamic>>() ?? [];

    // Safety guard (rare but safe)
    if (upperLip.length < 3 || lowerLip.length < 3) {
      return 'Please remove mask or face cover';
    }

    final upperAvgY = _avgY(upperLip);
    final lowerAvgY = _avgY(lowerLip);
    final mouthGap = (lowerAvgY - upperAvgY).abs();
    log('mouthGap: $mouthGap');

    // 🔑 Threshold tuning:
    //  - Mask → gap very small (2–5)
    //  - Normal → gap usually 8–20
    if (mouthGap < 5) {
      return 'Please remove mask or face cover';
    }

    return null; // ✅ FACE VALID
  }

  static double _avgY(List<List<dynamic>> points) {
    double sum = 0;
    for (final p in points) {
      sum += (p[1] as num).toDouble();
    }
    return sum / points.length;
  }
}

// class FaceRules {
//   static String? validate(Map<String, dynamic> data) {
//     print('FaceRules.validate: $data');

//     if ((data['faceCount'] ?? 0) == 0) {
//       return 'No face detected';
//     }

//     if ((data['faceCount'] ?? 0) > 1) {
//       return 'Multiple faces detected';
//     }

//     final yaw = (data['yaw'] ?? 0).toDouble();
//     if (yaw.abs() > 15) {
//       return 'Please look straight at the camera';
//     }

//     final leftEye = (data['leftEyeOpen'] ?? 1.0).toDouble();
//     final rightEye = (data['rightEyeOpen'] ?? 1.0).toDouble();
//     if (leftEye < 0.2 || rightEye < 0.2) {
//       return 'Please make sure your eyes are visible';
//     }

//     if (data['hasNose'] == false) {
//       return 'Please remove mask or face cover';
//     }

//     final upperLip = (data['upperLipPoints'] as List?)?.cast<List<dynamic>>() ?? [];
//     final lowerLip = (data['lowerLipPoints'] as List?)?.cast<List<dynamic>>() ?? [];

//     if (upperLip.isEmpty || lowerLip.isEmpty) {
//       return 'Please remove mask or face cover';
//     }

//     final upperAvgY = _avgY(upperLip);
//     final lowerAvgY = _avgY(lowerLip);

//     final mouthGap = (lowerAvgY - upperAvgY).abs();

//     if (mouthGap < 6) {
//       return 'Please remove mask or face cover';
//     }

//     return null; // ✅ PASS
//   }

//   static double _avgY(List<List<dynamic>> points) {
//     return points.map((p) => (p[1] as num).toDouble()).reduce((a, b) => a + b) / points.length;
//   }
// }
