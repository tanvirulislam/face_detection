import 'dart:io';

import 'package:tensorflow_face_verification/tensorflow_face_verification.dart';

Future<bool> isSamePerson(String imagePath1, String imagePath2, {double threshold = 0.6}) async {
  try {
    final isSame = await FaceVerification.instance.verifySamePerson(
      File(imagePath1),
      File(imagePath2),
      threshold: threshold,
    );

    print('Same person? $isSame');
    return isSame;
  } catch (e) {
    print('❌ Face verification failed: $e');
    rethrow;
  }
}

Future<double> compareFaces(String imagePath1, String imagePath2) async {
  try {
    final score = await FaceVerification.instance.getSimilarityScoreFromFile(File(imagePath1), File(imagePath2));

    print('Similarity score: $score');
    return score;
  } catch (e) {
    print('❌ Face comparison failed: $e');
    rethrow;
  }
}
