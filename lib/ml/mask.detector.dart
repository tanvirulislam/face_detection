import 'dart:developer';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MaskDetector {
  late Interpreter _interpreter;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset('assets/model/model.tflite', options: InterpreterOptions()..threads = 4);
  }

  /// Returns true if MASK is detected
  bool detectMask(File faceImage) {
    final bytes = faceImage.readAsBytesSync();
    final image = img.decodeImage(bytes)!;

    // Resize to model input
    final resized = img.copyResize(image, width: 224, height: 224);

    // Normalize image
    final input = List.generate(
      1,
      (_) => List.generate(
        224,
        (y) => List.generate(224, (x) {
          final pixel = resized.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );

    final output = List.filled(2, 0.0).reshape([1, 2]);
    _interpreter.run(input, output);

    final maskScore = output[0][0];
    final noMaskScore = output[0][1];

    // Apply decision
    final hasMask = maskScore > noMaskScore;

    log('maskScore: $maskScore, noMaskScore: $noMaskScore, hasMask: $hasMask');

    return maskScore > noMaskScore;
  }

  void close() {
    _interpreter.close();
  }
}
