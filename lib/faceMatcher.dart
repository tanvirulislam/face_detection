// import 'dart:math';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// class FaceMatcher {
//   Face? _referenceFace;

//   void setReferenceFace(Face face) {
//     _referenceFace = face;
//   }

//   /// Check if the current face matches the reference face
//   double matchFace(Face currentFace) {
//     if (_referenceFace == null) return 1.0;

//     // Use features that are stable across different head angles
//     double aspectScore = _compareAspectRatio(_referenceFace!, currentFace);
//     double eyeDistanceScore = _compareEyeDistance(_referenceFace!, currentFace);
//     double faceProportionScore = _compareFaceProportions(_referenceFace!, currentFace);

//     // Weighted average - focus on stable features
//     return (aspectScore * 0.35) + (eyeDistanceScore * 0.35) + (faceProportionScore * 0.30);
//   }

//   /// Compare face bounding box aspect ratio (width/height ratio is stable)
//   double _compareAspectRatio(Face ref, Face current) {
//     final refAspect = ref.boundingBox.width / ref.boundingBox.height;
//     final curAspect = current.boundingBox.width / current.boundingBox.height;

//     final diff = (refAspect - curAspect).abs() / refAspect;
//     return 1.0 - (diff * 1.5).clamp(0.0, 1.0);
//   }

//   /// Compare distance between eyes (very stable feature across angles)
//   double _compareEyeDistance(Face ref, Face current) {
//     final refLeftEye = ref.landmarks[FaceLandmarkType.leftEye];
//     final refRightEye = ref.landmarks[FaceLandmarkType.rightEye];
//     final curLeftEye = current.landmarks[FaceLandmarkType.leftEye];
//     final curRightEye = current.landmarks[FaceLandmarkType.rightEye];

//     if (refLeftEye == null || refRightEye == null || curLeftEye == null || curRightEye == null) {
//       return 0.5; // Can't compare, give neutral score
//     }

//     // Calculate eye distance normalized by face width
//     final refEyeDist =
//         sqrt(
//           pow(refRightEye.position.x - refLeftEye.position.x, 2) +
//               pow(refRightEye.position.y - refLeftEye.position.y, 2),
//         ) /
//         ref.boundingBox.width;

//     final curEyeDist =
//         sqrt(
//           pow(curRightEye.position.x - curLeftEye.position.x, 2) +
//               pow(curRightEye.position.y - curLeftEye.position.y, 2),
//         ) /
//         current.boundingBox.width;

//     final diff = (refEyeDist - curEyeDist).abs() / refEyeDist;
//     return 1.0 - (diff * 2.0).clamp(0.0, 1.0);
//   }

//   /// Compare key face proportions (stable across angles)
//   double _compareFaceProportions(Face ref, Face current) {
//     final refNose = ref.landmarks[FaceLandmarkType.noseBase];
//     final curNose = current.landmarks[FaceLandmarkType.noseBase];
//     final refLeftEye = ref.landmarks[FaceLandmarkType.leftEye];
//     final curLeftEye = current.landmarks[FaceLandmarkType.leftEye];

//     if (refNose == null || curNose == null || refLeftEye == null || curLeftEye == null) {
//       return 0.5;
//     }

//     // Nose-to-eye distance ratio (normalized by face height)
//     final refNoseEyeDist =
//         sqrt(pow(refNose.position.x - refLeftEye.position.x, 2) + pow(refNose.position.y - refLeftEye.position.y, 2)) /
//         ref.boundingBox.height;

//     final curNoseEyeDist =
//         sqrt(pow(curNose.position.x - curLeftEye.position.x, 2) + pow(curNose.position.y - curLeftEye.position.y, 2)) /
//         current.boundingBox.height;

//     final diff = (refNoseEyeDist - curNoseEyeDist).abs() / refNoseEyeDist;
//     return 1.0 - (diff * 2.0).clamp(0.0, 1.0);
//   }

//   void reset() {
//     _referenceFace = null;
//   }
// }
