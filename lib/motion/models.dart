import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';

// ═══════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════

enum FaceType { front, back }

enum LiveStep { lookStraight, blinkEyes, turnLeft, turnRight, smile }

// ADD lowLight here ↓
enum FaceWarning {
  none,
  maskCovering,
  sunglasses,
  eyeglasses,
  nudity,
  lowLight, // ← THIS LINE MUST BE HERE
  eyesClosed, // ← ADD THIS
}

// ═══════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════

class StepConfig {
  final LiveStep step;
  final String instruction;
  final IconData icon;
  final Color color;

  const StepConfig(this.step, this.instruction, this.icon, this.color);
}

const List<StepConfig> kSteps = [
  StepConfig(LiveStep.lookStraight, 'Look straight at the camera', Icons.face, Color(0xFF2196F3)),
  StepConfig(LiveStep.blinkEyes, 'Blink your eyes twice', Icons.remove_red_eye, Color(0xFF9C27B0)),
  StepConfig(LiveStep.turnLeft, 'Slowly turn head LEFT ⬅️', Icons.arrow_back, Color(0xFFFF9800)),
  StepConfig(LiveStep.turnRight, 'Slowly turn head RIGHT ➡️', Icons.arrow_forward, Color(0xFFFF5722)),
  StepConfig(LiveStep.smile, 'Give a natural smile 😊', Icons.sentiment_satisfied, Color(0xFF4CAF50)),
];

class FaceGuardResult {
  final FaceWarning warning;
  final String message;
  final bool blockStep;

  const FaceGuardResult({required this.warning, required this.message, required this.blockStep});

  static const ok = FaceGuardResult(warning: FaceWarning.none, message: '', blockStep: false);
}

class VerificationResult {
  final XFile frontImage;
  final XFile leftImage;
  final XFile rightImage;

  VerificationResult({required this.frontImage, required this.leftImage, required this.rightImage});
}

// ═══════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════

class OvalUtils {
  static const double centerYFactor = 0.46;
  static const double widthFactor = 0.72;
  static const double heightFactor = 0.52;

  static Rect ovalRect(Size size, {double scale = 1.0}) {
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * centerYFactor),
      width: size.width * widthFactor * scale,
      height: size.height * heightFactor * scale,
    );
  }
}
