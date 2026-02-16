// Add this class to models.dart
import 'package:camera/camera.dart';

class VerificationResult {
  final XFile frontImage;
  final XFile leftImage;
  final XFile rightImage;

  VerificationResult({required this.frontImage, required this.leftImage, required this.rightImage});
}
