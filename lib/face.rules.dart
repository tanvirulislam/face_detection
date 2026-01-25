class FaceRules {
  static String? validate(Map<String, dynamic> data) {
    print('camera data: $data');
    if ((data['faceCount'] ?? 0) == 0) {
      return 'No face detected';
    }

    if ((data['faceCount'] ?? 0) > 1) {
      return 'Multiple faces detected';
    }

    final yaw = (data['yaw'] ?? 0).toDouble();
    if (yaw.abs() > 15) {
      return 'Please look straight at the camera';
    }

    final leftEye = (data['leftEyeOpen'] ?? 1.0).toDouble();
    final rightEye = (data['rightEyeOpen'] ?? 1.0).toDouble();
    if (leftEye < 0.2 || rightEye < 0.2) {
      return 'Please remove sunglasses';
    }

    if (data['hasNose'] == false || data['hasMouth'] == false) {
      return 'Please remove mask or face cover';
    }

    return null; // ✅ PASS
  }
}
