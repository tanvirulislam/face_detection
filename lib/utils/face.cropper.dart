import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Crops face for mask detection using ML Kit bounding box
/// Returns a 224x224 image ready for TFLite
Future<File> cropFaceForMask({
  required String imagePath,
  required Map<String, dynamic> faceBox,
  bool saveDebugImage = true, // optional: save resized crop for debugging
}) async {
  final bytes = await File(imagePath).readAsBytes();
  final original = img.decodeImage(bytes);

  if (original == null) {
    throw Exception('Failed to decode image');
  }

  // ML Kit bounding box
  int left = faceBox['left'];
  int top = faceBox['top'];
  int right = faceBox['right'];
  int bottom = faceBox['bottom'];

  // Clamp values
  left = left.clamp(0, original.width - 1);
  top = top.clamp(0, original.height - 1);
  right = right.clamp(0, original.width);
  bottom = bottom.clamp(0, original.height);

  int width = right - left;
  int height = bottom - top;

  // 🔹 Improve crop for mask region:
  // Extend slightly downward to cover nose & mouth
  int extendDown = (height * 0.25).toInt();
  bottom = (bottom + extendDown).clamp(0, original.height);
  height = bottom - top;

  // Optional: shrink top slightly to remove forehead
  int shrinkTop = (height * 0.15).toInt();
  top = (top + shrinkTop).clamp(0, original.height);
  height = bottom - top;

  // Crop face region
  final cropped = img.copyCrop(original, x: left, y: top, width: width, height: height);

  // Resize to 224x224 for TFLite
  final resized = img.copyResize(cropped, width: 224, height: 224);

  // Save cropped image
  final croppedFile = File(imagePath.replaceFirst('.jpg', '_face.jpg'));
  await croppedFile.writeAsBytes(img.encodeJpg(resized, quality: 95));

  // Optional: debug image
  if (saveDebugImage) {
    final directory = await getExternalStorageDirectory();
    final debugPath = '${directory!.path}/debug_faces';

    // Create directory if it doesn't exist
    await Directory(debugPath).create(recursive: true);

    final debugFile = File('$debugPath/face_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await debugFile.writeAsBytes(img.encodeJpg(resized, quality: 95));
    // log('Saved debug image at: ${debugFile.path}');
  }

  return croppedFile;
}
