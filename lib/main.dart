import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Detection Validation',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FaceDetectionScreen(cameras: cameras),
    );
  }
}

class FaceDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceDetectionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isProcessing = false;
  String _validationMessage = '';
  Color _messageColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
  }

  void _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    // Use front camera
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);

    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _captureAndValidate() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showMessage('Camera not initialized', Colors.red);
      return;
    }

    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _validationMessage = 'Processing...';
      _messageColor = Colors.orange;
    });

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);

      final faces = await _faceDetector.processImage(inputImage);

      final validationResult = _validateFaces(faces);

      setState(() {
        _validationMessage = validationResult.message;
        _messageColor = validationResult.isValid ? Colors.green : Colors.red;
      });

      if (validationResult.isValid) {
        _showSuccessDialog(imageFile.path);
      }
    } catch (e) {
      _showMessage('Error: $e', Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  ValidationResult _validateFaces(List<Face> faces) {
    // Validation 1: Check if face exists
    if (faces.isEmpty) {
      return ValidationResult(isValid: false, message: '❌ No face detected! Please ensure your face is visible.');
    }

    // Validation 2: Check for multiple faces
    if (faces.length > 1) {
      return ValidationResult(
        isValid: false,
        message: '❌ Multiple faces detected! Only one person should be in frame.',
      );
    }

    final face = faces.first;

    // Validation 3: Check if face is frontal
    final headEulerAngleY = face.headEulerAngleY; // Left-Right rotation
    final headEulerAngleZ = face.headEulerAngleZ; // Tilt

    if (headEulerAngleY == null || headEulerAngleZ == null) {
      return ValidationResult(isValid: false, message: '❌ Cannot determine face orientation.');
    }

    // Check if face is looking straight (front facing)
    if (headEulerAngleY!.abs() > 15 || headEulerAngleZ!.abs() > 15) {
      return ValidationResult(isValid: false, message: '❌ Face not frontal! Please look directly at the camera.');
    }

    // Validation 4: Check for eyes visibility and sunglasses (STRICTER)
    final leftEyeOpenProbability = face.leftEyeOpenProbability;
    final rightEyeOpenProbability = face.rightEyeOpenProbability;

    // Both eyes must be detected and visible
    if (leftEyeOpenProbability == null || rightEyeOpenProbability == null) {
      return ValidationResult(isValid: false, message: '❌ Eyes not detected! Remove sunglasses or obstructions.');
    }

    // Stricter eye visibility check - both eyes should be clearly open
    if (leftEyeOpenProbability < 0.5 || rightEyeOpenProbability < 0.5) {
      return ValidationResult(
        isValid: false,
        message: '❌ Eyes not clearly visible! Remove sunglasses or keep eyes open.',
      );
    }

    // Validation 5: Check ALL facial landmarks are detected (CRITICAL)
    final requiredLandmarks = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
    ];

    for (var landmarkType in requiredLandmarks) {
      if (face.landmarks[landmarkType] == null) {
        return ValidationResult(
          isValid: false,
          message: '❌ Face partially covered! Remove mask, hand, or any obstruction.',
        );
      }
    }

    // Validation 6: Check mouth visibility with geometric validation
    final mouthBottom = face.landmarks[FaceLandmarkType.bottomMouth];
    final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth];
    final mouthRight = face.landmarks[FaceLandmarkType.rightMouth];
    final noseBase = face.landmarks[FaceLandmarkType.noseBase];

    if (mouthBottom == null || mouthLeft == null || mouthRight == null || noseBase == null) {
      return ValidationResult(isValid: false, message: '❌ Mouth or nose not visible! Remove mask or face covering.');
    }

    // CRITICAL: Check the distance between nose and mouth
    // If mouth is covered, this distance becomes abnormal
    final noseToMouthDistance = (noseBase.position.y - mouthBottom.position.y).abs();
    final mouthWidth = (mouthLeft.position.x - mouthRight.position.x).abs();

    // Normal nose-to-mouth distance should be reasonable
    // If it's too small, mouth is likely covered
    if (noseToMouthDistance < 30) {
      return ValidationResult(isValid: false, message: '❌ Mouth appears covered! Please remove mask.');
    }

    // Check mouth width - if too small, might be covered
    if (mouthWidth < 40) {
      return ValidationResult(isValid: false, message: '❌ Mouth not properly visible! Remove any covering.');
    }

    // Validation 7: CRITICAL - Check smiling probability for mouth detection
    final smilingProbability = face.smilingProbability;

    // If smiling probability cannot be determined, mouth is likely covered
    if (smilingProbability == null) {
      return ValidationResult(
        isValid: false,
        message: '❌ Facial expression not detected! Remove mask or face covering.',
      );
    }

    // Validation 8: Check contours for mouth area (MOST IMPORTANT)
    final upperLipBottom = face.contours[FaceContourType.upperLipBottom];
    final lowerLipTop = face.contours[FaceContourType.lowerLipTop];
    final upperLipTop = face.contours[FaceContourType.upperLipTop];
    final lowerLipBottom = face.contours[FaceContourType.lowerLipBottom];

    // DEBUG: Log lip contour information
    print('🔍 DEBUG - Lip Contours:');
    print('upperLipBottom: ${upperLipBottom?.points.length ?? "NULL"}');
    print('lowerLipTop: ${lowerLipTop?.points.length ?? "NULL"}');
    print('upperLipTop: ${upperLipTop?.points.length ?? "NULL"}');
    print('lowerLipBottom: ${lowerLipBottom?.points.length ?? "NULL"}');
    print('smilingProbability: ${face.smilingProbability ?? "NULL"}');
    print('noseToMouthDistance: $noseToMouthDistance');
    print('mouthWidth: $mouthWidth');

    // All lip contours MUST be detected
    if (upperLipBottom == null || lowerLipTop == null || upperLipTop == null || lowerLipBottom == null) {
      return ValidationResult(isValid: false, message: '❌ Lips not detected! Please remove mask completely.');
    }

    // Check if lip contours have sufficient points (relaxed threshold)
    if (upperLipBottom.points.length < 2 || lowerLipTop.points.length < 2) {
      return ValidationResult(isValid: false, message: '❌ Mouth area obscured! Remove any face covering.');
    }

    // Validation 9: Validate nose contour
    final noseBridge = face.contours[FaceContourType.noseBridge];
    final noseBottom = face.contours[FaceContourType.noseBottom];

    if (noseBridge == null || noseBottom == null) {
      return ValidationResult(isValid: false, message: '❌ Nose not clearly visible! Remove mask or obstruction.');
    }

    if (noseBridge.points.length < 1 || noseBottom.points.length < 2) {
      return ValidationResult(isValid: false, message: '❌ Nose area partially covered! Remove face covering.');
    }

    // Validation 10: Check face contour completeness
    final faceContour = face.contours[FaceContourType.face];

    if (faceContour == null) {
      return ValidationResult(isValid: false, message: '❌ Face outline not detected! Remove any obstruction.');
    }

    // Face contour should have many points for a clear, unobstructed face
    if (faceContour.points.length < 20) {
      return ValidationResult(isValid: false, message: '❌ Face not fully visible! Remove hands or coverings.');
    }

    // Validation 11: Check left and right cheek contours (optional - may not always be detected)
    final leftCheek = face.contours[FaceContourType.leftCheek];
    final rightCheek = face.contours[FaceContourType.rightCheek];

    // Only validate if cheek contours are available
    if (leftCheek != null && rightCheek != null) {
      if (leftCheek.points.isEmpty || rightCheek.points.isEmpty) {
        return ValidationResult(isValid: false, message: '❌ Face partially obscured! Remove all coverings.');
      }
    }
    // Note: Cheek contours often have only 1 point, which is acceptable

    // Validation 12: Face size validation
    final boundingBox = face.boundingBox;
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;

    if (faceWidth < 200 || faceHeight < 200) {
      return ValidationResult(isValid: false, message: '❌ Face too small! Please move closer to the camera.');
    }

    if (faceWidth > 800 || faceHeight > 800) {
      return ValidationResult(isValid: false, message: '❌ Face too close! Please move back a bit.');
    }

    // Validation 13: Cross-check eye landmarks with eye contours
    final leftEyeContour = face.contours[FaceContourType.leftEye];
    final rightEyeContour = face.contours[FaceContourType.rightEye];

    if (leftEyeContour == null || rightEyeContour == null) {
      return ValidationResult(isValid: false, message: '❌ Eye contours not detected! Remove sunglasses.');
    }

    if (leftEyeContour.points.length < 5 || rightEyeContour.points.length < 5) {
      return ValidationResult(isValid: false, message: '❌ Eyes partially obscured! Remove sunglasses or obstructions.');
    }

    // All validations passed
    return ValidationResult(isValid: true, message: '✅ Perfect! Face validated successfully.');
  }

  void _showMessage(String message, Color color) {
    setState(() {
      _validationMessage = message;
      _messageColor = color;
    });
  }

  void _showSuccessDialog(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✅ Validation Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(File(imagePath), height: 200),
            const SizedBox(height: 16),
            const Text('Face has been validated successfully!'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection Validation'), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_cameraController!)),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                if (_validationMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _messageColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _messageColor),
                    ),
                    child: Text(
                      _validationMessage,
                      style: TextStyle(color: _messageColor, fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _captureAndValidate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Capture & Validate', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Instructions:\n'
                  '• Look directly at the camera\n'
                  '• Remove sunglasses and mask\n'
                  '• Do not cover face with hands\n'
                  '• Keep mouth and eyes visible\n'
                  '• Ensure proper lighting\n'
                  '• Only one person in frame',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ValidationResult {
  final bool isValid;
  final String message;

  ValidationResult({required this.isValid, required this.message});
}
