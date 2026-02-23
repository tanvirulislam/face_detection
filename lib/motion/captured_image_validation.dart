import 'dart:developer' as dev;
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'models.dart';
import 'services.dart';

// ═══════════════════════════════════════════════════════════
// CAPTURE VALIDATION RESULT
// ═══════════════════════════════════════════════════════════

class CaptureValidationResult {
  final bool isValid;
  final String? failureReason;
  final double? detectedYaw;
  final FaceWarning? warning;

  const CaptureValidationResult({required this.isValid, this.failureReason, this.detectedYaw, this.warning});

  static const valid = CaptureValidationResult(isValid: true);
}

// ═══════════════════════════════════════════════════════════
// CAPTURED IMAGE VALIDATOR
// ═══════════════════════════════════════════════════════════

/// Runs ALL checks on a captured [XFile] before accepting it:
///
///  1. Face presence & uniqueness
///  2. Face containment in oval (IoF ≥ 0.75)
///  3. Brightness / low-light  (pixel sampling from JPEG bytes)
///  4. FaceGuard — nudity, mask/hand, sunglasses, glasses
///  5. Eyes open (lookStraight step only)
///  6. Pose angle (yaw) matches expected [LiveStep]
class CapturedImageValidator {
  final FaceDetector _detector;
  final ImageLabeler _labeler;

  // Isolated instances so their rolling windows don't mix with the live stream.
  final FaceGuard _guard = FaceGuard();
  final BrightnessChecker _brightness = BrightnessChecker();

  CapturedImageValidator()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: Platform.isAndroid ? FaceDetectorMode.accurate : FaceDetectorMode.fast,
          enableLandmarks: true,
          enableClassification: true,
        ),
      ),
      _labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));

  // ─────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────

  /// Validate [file] captured during [step].
  /// [screenSize] is used for oval containment geometry.
  Future<CaptureValidationResult> validate(XFile file, LiveStep step, Size screenSize) async {
    _guard.reset();
    _brightness.reset();

    try {
      final inputImage = InputImage.fromFilePath(file.path);

      // ── 1. Detect faces ──
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) {
        return _fail('No face detected in captured image', FaceWarning.none);
      }
      if (faces.length > 1) {
        return _fail('More than one face in captured image — only one person allowed', FaceWarning.none);
      }

      final face = faces.first;

      // ── 2. Run image labeler ──
      final labels = await _labeler.processImage(inputImage);
      dev.log('📸 Labels: ${labels.map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').join(', ')}');

      // ── 3. Brightness check (JPEG byte sampling) ──
      final brightnessFailure = await _checkFileBrightness(file);
      if (brightnessFailure != null) {
        dev.log('📸 Brightness fail: $brightnessFailure');
        return _fail(brightnessFailure, FaceWarning.lowLight);
      }

      // ── 4. Landmark presence ──
      final hasNose = face.landmarks[FaceLandmarkType.noseBase] != null;
      final hasMouth =
          face.landmarks[FaceLandmarkType.leftMouth] != null || face.landmarks[FaceLandmarkType.rightMouth] != null;

      // ── 5. Yaw — apply same inversion as live stream ──
      double yaw = face.headEulerAngleY ?? 0.0;
      if (Platform.isAndroid) yaw = -yaw;

      // ── 6. Oval containment (IoF) ──
      final iof = _computeIof(face, inputImage, screenSize);
      dev.log('📸 IoF=${iof.toStringAsFixed(2)}  yaw=${yaw.toStringAsFixed(1)}°');

      // ── 7. FaceGuard — nudity / mask / sunglasses / glasses ──
      final guardResult = _guard.check(
        face: face,
        labels: labels,
        hasNose: hasNose,
        hasMouth: hasMouth,
        yaw: yaw,
        faceInOval: iof >= 0.75,
      );

      if (guardResult.blockStep) {
        dev.log('📸 Guard fail: ${guardResult.message}');
        return _fail(guardResult.message, guardResult.warning);
      }

      // ── 8. Face centred in oval ──
      if (iof < 0.75) {
        return _fail('Face not centred in oval — please reposition', FaceWarning.none);
      }

      // ── 9. Eyes open (lookStraight only) ──
      if (step == LiveStep.lookStraight) {
        final leftEye = face.leftEyeOpenProbability ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        final thresh = Platform.isAndroid ? 0.35 : 0.4;
        if (leftEye < thresh || rightEye < thresh) {
          return _fail('Eyes appear closed — keep eyes open 👀', FaceWarning.eyesClosed);
        }
      }

      // ── 10. Pose angle ──
      final poseResult = _checkPose(yaw, step);
      if (!poseResult.isValid) return poseResult;

      dev.log('✅ Capture fully validated: step=$step yaw=${yaw.toStringAsFixed(1)}°');
      return CaptureValidationResult(isValid: true, detectedYaw: yaw);
    } catch (e) {
      dev.log('📸 Validation error: $e');
      return _fail('Validation failed — please retry', FaceWarning.none);
    }
  }

  void dispose() {
    _detector.close();
    _labeler.close();
  }

  // ─────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────

  CaptureValidationResult _fail(String reason, FaceWarning? warning) =>
      CaptureValidationResult(isValid: false, failureReason: reason, warning: warning);

  // ── Pose angle check ──
  CaptureValidationResult _checkPose(double yaw, LiveStep step) {
    switch (step) {
      case LiveStep.lookStraight:
        if (yaw.abs() <= 22) return CaptureValidationResult(isValid: true, detectedYaw: yaw);
        return _fail('Face not straight (${yaw.toStringAsFixed(1)}°) — look directly at camera', FaceWarning.none);

      case LiveStep.turnLeft:
        final isLeft = Platform.isAndroid ? yaw < -15 : yaw > 15;
        if (isLeft) return CaptureValidationResult(isValid: true, detectedYaw: yaw);
        return _fail('Head not turned left enough — turn more to the LEFT ⬅️', FaceWarning.none);

      case LiveStep.turnRight:
        final isRight = Platform.isAndroid ? yaw > 15 : yaw < -15;
        if (isRight) return CaptureValidationResult(isValid: true, detectedYaw: yaw);
        return _fail('Head not turned right enough — turn more to the RIGHT ➡️', FaceWarning.none);

      case LiveStep.blinkEyes:
        return CaptureValidationResult.valid;
    }
  }

  // ── IoF: face bounding box vs oval, mapped to screen coords ──
  double _computeIof(Face face, InputImage inputImage, Size screenSize) {
    try {
      final imgSize = inputImage.metadata?.size ?? screenSize;
      final double imgW = imgSize.width;
      final double imgH = imgSize.height;

      final double coverScale = [screenSize.width / imgW, screenSize.height / imgH].reduce((a, b) => a > b ? a : b);

      final double scaledW = imgW * coverScale;
      final double scaledH = imgH * coverScale;
      final double offsetX = (scaledW - screenSize.width) / 2;
      final double offsetY = (scaledH - screenSize.height) / 2;

      final fb = face.boundingBox;
      double faceLeft = fb.left * coverScale - offsetX;
      double faceRight = fb.right * coverScale - offsetX;
      double faceTop = fb.top * coverScale - offsetY;
      double faceBottom = fb.bottom * coverScale - offsetY;

      // Front-camera saved JPEG is horizontally mirrored on iOS
      if (Platform.isIOS) {
        final ml = screenSize.width - faceRight;
        final mr = screenSize.width - faceLeft;
        faceLeft = ml;
        faceRight = mr;
      }

      final faceRect = Rect.fromLTRB(faceLeft, faceTop, faceRight, faceBottom);
      final oval = OvalUtils.ovalRect(screenSize);
      final intersection = faceRect.intersect(oval);
      final faceArea = faceRect.width * faceRect.height;

      if (faceArea <= 0) return 0.0;
      return (intersection.width.clamp(0.0, double.infinity) * intersection.height.clamp(0.0, double.infinity)) /
          faceArea;
    } catch (_) {
      return 1.0; // geometry failed — skip containment check
    }
  }

  // ── Brightness from JPEG byte sampling ──
  // Samples raw compressed bytes to estimate exposure.
  // Thresholds are tuned for JPEG (lower values than NV21 raw Y plane).
  Future<String?> _checkFileBrightness(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      int sum = 0;
      int count = 0;

      // Skip first 500 bytes (JPEG headers are always near 0xFF and skew results)
      for (int i = 500; i < bytes.length - 1; i += 4000) {
        if (bytes[i] == 0xFF) continue; // skip marker bytes
        sum += bytes[i];
        count++;
      }

      if (count == 0) return null;
      final avg = sum / count;
      dev.log('📸 File brightness avg=$avg (count=$count)');

      if (avg < 28) return '⚠️ Image too dark — move to a brighter area';
      if (avg < 48) return '💡 Low light in captured image — better lighting needed';
      return null;
    } catch (e) {
      dev.log('📸 Brightness read error: $e');
      return null; // don't block on read failure
    }
  }
}
