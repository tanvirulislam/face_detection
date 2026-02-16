import 'dart:developer' as dev; // Add 'as dev' prefix
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'models.dart';

// ═══════════════════════════════════════════════════════════
// FACE GUARD
// ═══════════════════════════════════════════════════════════

class FaceGuard {
  static const int _sunglassWindow = 20;
  static const double _sunglassMaxThresh = 0.45;
  final List<double> _eyeMaxHistory = [];

  static const _nudityLabels = ['nudity', 'nude', 'naked', 'underwear', 'bikini', 'swimwear', 'lingerie', 'topless'];
  static const _maskLabels = ['mask', 'face mask', 'surgical mask', 'respirator', 'hand'];
  static const _sunglassLabels = ['sunglasses', 'goggles'];
  static const _glassLabels = ['glasses', 'spectacles', 'eyewear'];

  FaceGuardResult check({
    required Face face,
    required List<ImageLabel> labels,
    required bool hasNose,
    required bool hasMouth,
  }) {
    // Check nudity
    for (final l in labels) {
      if (_nudityLabels.any((n) => l.label.toLowerCase().contains(n)) && l.confidence > 0.6) {
        dev.log('🚫 Nudity: ${l.label} (${l.confidence.toStringAsFixed(2)})'); // Changed to dev.log
        return const FaceGuardResult(
          warning: FaceWarning.nudity,
          message: '🚫 Nudity detected. Please dress appropriately.',
          blockStep: true,
        );
      }
    }

    // Check mask/hand
    for (final l in labels) {
      if (_maskLabels.any((m) => l.label.toLowerCase().contains(m)) && l.confidence > 0.55) {
        dev.log('⚠️ Mask/hand: ${l.label} (${l.confidence.toStringAsFixed(2)})'); // Changed to dev.log
        return const FaceGuardResult(
          warning: FaceWarning.maskCovering,
          message: '⚠️ Remove mask or hand from face.',
          blockStep: true,
        );
      }
    }

    if (!hasNose && !hasMouth) {
      return const FaceGuardResult(
        warning: FaceWarning.maskCovering,
        message: '⚠️ Face appears covered. Remove mask or hand.',
        blockStep: true,
      );
    }
    if (!hasMouth && hasNose) {
      return const FaceGuardResult(
        warning: FaceWarning.maskCovering,
        message: '⚠️ Remove face mask to continue.',
        blockStep: true,
      );
    }

    // Eye-based sunglasses detection
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    _eyeMaxHistory.add(leftEye > rightEye ? leftEye : rightEye);
    if (_eyeMaxHistory.length > _sunglassWindow) _eyeMaxHistory.removeAt(0);

    if (_eyeMaxHistory.length >= _sunglassWindow) {
      final maxVal = _eyeMaxHistory.reduce((a, b) => a > b ? a : b);
      if (maxVal < _sunglassMaxThresh) {
        dev.log('🕶 Dark lenses — max eye: $maxVal'); // Changed to dev.log
        return const FaceGuardResult(
          warning: FaceWarning.sunglasses,
          message: '🕶 Remove sunglasses to continue.',
          blockStep: true,
        );
      }
    }

    // Label-based sunglasses detection
    for (final l in labels) {
      if (_sunglassLabels.any((s) => l.label.toLowerCase().contains(s)) && l.confidence > 0.60) {
        dev.log('🕶 Sunglasses: ${l.label} (${l.confidence.toStringAsFixed(2)})'); // Changed to dev.log
        return const FaceGuardResult(
          warning: FaceWarning.sunglasses,
          message: '🕶 Remove sunglasses to continue.',
          blockStep: true,
        );
      }
    }

    // Label-based glasses detection
    for (final l in labels) {
      if (_glassLabels.any((g) => l.label.toLowerCase().contains(g)) && l.confidence > 0.65) {
        dev.log('👓 Glasses: ${l.label} (${l.confidence.toStringAsFixed(2)})'); // Changed to dev.log
        return const FaceGuardResult(
          warning: FaceWarning.eyeglasses,
          message: '👓 Remove glasses to continue.',
          blockStep: true,
        );
      }
    }

    return FaceGuardResult.ok;
  }

  void reset() => _eyeMaxHistory.clear();
}

// ═══════════════════════════════════════════════════════════
// BLINK DETECTOR
// ═══════════════════════════════════════════════════════════

class BlinkDetector {
  static const double _closedThreshold = 0.35;
  static const double _openThreshold = 0.80;
  static const int _cooldownMs = 600;

  int _blinkCount = 0;
  bool _inBlink = false;
  bool _cooldown = false;
  DateTime? _blinkStart;

  int get blinkCount => _blinkCount;

  bool update(double? l, double? r) {
    final avg = ((l ?? 1.0) + (r ?? 1.0)) / 2.0;
    if (_cooldown) return false;

    if (!_inBlink) {
      if (avg < _closedThreshold) {
        _inBlink = true;
        _blinkStart = DateTime.now();
      }
    } else {
      if (avg > _openThreshold) {
        final ms = DateTime.now().difference(_blinkStart!).inMilliseconds;
        if (ms < 800) {
          _blinkCount++;
          dev.log('✅ Blink #$_blinkCount (${ms}ms)'); // Changed to dev.log
          _cooldown = true;
          Future.delayed(Duration(milliseconds: _cooldownMs), () => _cooldown = false);
        }
        _inBlink = false;
        return _blinkCount > 0;
      }
      if (DateTime.now().difference(_blinkStart!).inMilliseconds > 1000) _inBlink = false;
    }
    return false;
  }

  void reset() {
    _blinkCount = 0;
    _inBlink = false;
    _cooldown = false;
    _blinkStart = null;
  }
}

// ═══════════════════════════════════════════════════════════
// FACE MATCHER
// ═══════════════════════════════════════════════════════════

class FaceMatcher {
  Face? _referenceFace;

  void setReferenceFace(Face face) => _referenceFace = face;

  double matchFace(Face currentFace) {
    if (_referenceFace == null) return 1.0;

    double aspectScore = _compareAspectRatio(_referenceFace!, currentFace);
    double eyeDistanceScore = _compareEyeDistance(_referenceFace!, currentFace);
    double faceProportionScore = _compareFaceProportions(_referenceFace!, currentFace);

    return (aspectScore * 0.35) + (eyeDistanceScore * 0.35) + (faceProportionScore * 0.30);
  }

  double _compareAspectRatio(Face ref, Face current) {
    final refAspect = ref.boundingBox.width / ref.boundingBox.height;
    final curAspect = current.boundingBox.width / current.boundingBox.height;
    final diff = (refAspect - curAspect).abs() / refAspect;
    return 1.0 - (diff * 1.5).clamp(0.0, 1.0);
  }

  double _compareEyeDistance(Face ref, Face current) {
    final refLeftEye = ref.landmarks[FaceLandmarkType.leftEye];
    final refRightEye = ref.landmarks[FaceLandmarkType.rightEye];
    final curLeftEye = current.landmarks[FaceLandmarkType.leftEye];
    final curRightEye = current.landmarks[FaceLandmarkType.rightEye];

    if (refLeftEye == null || refRightEye == null || curLeftEye == null || curRightEye == null) {
      return 0.5;
    }

    final refEyeDist =
        sqrt(
          pow(refRightEye.position.x - refLeftEye.position.x, 2) +
              pow(refRightEye.position.y - refLeftEye.position.y, 2),
        ) /
        ref.boundingBox.width;

    final curEyeDist =
        sqrt(
          pow(curRightEye.position.x - curLeftEye.position.x, 2) +
              pow(curRightEye.position.y - curLeftEye.position.y, 2),
        ) /
        current.boundingBox.width;

    final diff = (refEyeDist - curEyeDist).abs() / refEyeDist;
    return 1.0 - (diff * 2.0).clamp(0.0, 1.0);
  }

  double _compareFaceProportions(Face ref, Face current) {
    final refNose = ref.landmarks[FaceLandmarkType.noseBase];
    final curNose = current.landmarks[FaceLandmarkType.noseBase];
    final refLeftEye = ref.landmarks[FaceLandmarkType.leftEye];
    final curLeftEye = current.landmarks[FaceLandmarkType.leftEye];

    if (refNose == null || curNose == null || refLeftEye == null || curLeftEye == null) {
      return 0.5;
    }

    final refNoseEyeDist =
        sqrt(pow(refNose.position.x - refLeftEye.position.x, 2) + pow(refNose.position.y - refLeftEye.position.y, 2)) /
        ref.boundingBox.height;

    final curNoseEyeDist =
        sqrt(pow(curNose.position.x - curLeftEye.position.x, 2) + pow(curNose.position.y - curLeftEye.position.y, 2)) /
        current.boundingBox.height;

    final diff = (refNoseEyeDist - curNoseEyeDist).abs() / refNoseEyeDist;
    return 1.0 - (diff * 2.0).clamp(0.0, 1.0);
  }

  void reset() => _referenceFace = null;
}

// ═══════════════════════════════════════════════════════════
// CAMERA UTILS
// ═══════════════════════════════════════════════════════════

class CameraUtils {
  static InputImage? toInputImage(CameraImage image, CameraDescription cam) {
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    } else {
      var c = cam.sensorOrientation;
      if (cam.lensDirection == CameraLensDirection.front) c = (360 - c) % 360;
      rotation = InputImageRotationValue.fromRawValue(c);
    }

    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    final all = image.planes.fold<List<int>>([], (p, pl) => p..addAll(pl.bytes));
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(all),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
}
