// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// class FaceVerificationScreen extends StatefulWidget {
//   const FaceVerificationScreen({Key? key}) : super(key: key);

//   @override
//   State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
// }

// class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
//   CameraController? _cameraController;
//   FaceDetector? _faceDetector;
//   bool _isDetecting = false;
//   bool _isCameraInitialized = false;

//   // Liveness detection states
//   List<LivenessStep> _livenessSteps = [];
//   int _currentStepIndex = 0;
//   bool _verificationComplete = false;
//   String _instruction = "Position your face in the frame";

//   // Face detection data
//   Face? _detectedFace;
//   bool _faceInFrame = false;

//   // Blink detection state
//   bool _wasEyesOpen = false;
//   bool _blinkDetected = false;

//   @override
//   void initState() {
//     super.initState();
//     _initializeLivenessSteps();
//     _initializeCamera();
//     _initializeFaceDetector();
//   }

//   void _initializeLivenessSteps() {
//     _livenessSteps = [
//       LivenessStep(
//         type: LivenessType.lookStraight,
//         instruction: "Look straight at the camera",
//         duration: Duration(seconds: 2),
//       ),
//       LivenessStep(type: LivenessType.blink, instruction: "Blink your eyes", duration: Duration(seconds: 3)),
//       LivenessStep(type: LivenessType.smile, instruction: "Smile naturally", duration: Duration(seconds: 2)),
//       LivenessStep(
//         type: LivenessType.turnLeft,
//         instruction: "Turn your head slightly left",
//         duration: Duration(seconds: 2),
//       ),
//       LivenessStep(
//         type: LivenessType.turnRight,
//         instruction: "Turn your head slightly right",
//         duration: Duration(seconds: 2),
//       ),
//     ];
//   }

//   void _initializeFaceDetector() {
//     final options = FaceDetectorOptions(
//       enableContours: true,
//       enableClassification: true,
//       enableTracking: true,
//       minFaceSize: 0.15,
//       performanceMode: FaceDetectorMode.accurate,
//     );
//     _faceDetector = FaceDetector(options: options);
//   }

//   Future<void> _initializeCamera() async {
//     try {
//       final cameras = await availableCameras();
//       final frontCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front);

//       _cameraController = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);

//       await _cameraController!.initialize();

//       if (mounted) {
//         setState(() {
//           _isCameraInitialized = true;
//         });

//         _cameraController!.startImageStream(_processCameraImage);
//       }
//     } catch (e) {
//       debugPrint('Error initializing camera: $e');
//     }
//   }

//   Future<void> _processCameraImage(CameraImage cameraImage) async {
//     if (_isDetecting || _verificationComplete || !mounted) return;

//     _isDetecting = true;

//     try {
//       final inputImage = _convertCameraImage(cameraImage);
//       if (inputImage == null) {
//         _isDetecting = false;
//         return;
//       }

//       final faces = await _faceDetector!.processImage(inputImage);

//       if (!mounted) {
//         _isDetecting = false;
//         return;
//       }

//       if (faces.isEmpty) {
//         setState(() {
//           _faceInFrame = false;
//           _instruction = "No face detected. Please position your face";
//         });
//       } else if (faces.length > 1) {
//         setState(() {
//           _faceInFrame = false;
//           _instruction = "Multiple faces detected. Only one person allowed";
//         });
//       } else {
//         final face = faces.first;
//         _detectedFace = face;
//         _faceInFrame = true;

//         await _checkLivenessStep(face);
//       }
//     } catch (e) {
//       debugPrint('Error processing image: $e');
//     }

//     _isDetecting = false;
//   }

//   InputImage? _convertCameraImage(CameraImage cameraImage) {
//     try {
//       final camera = _cameraController!.description;

//       // Get image rotation for iOS
//       final sensorOrientation = camera.sensorOrientation;
//       InputImageRotation? rotation;

//       if (Platform.isIOS) {
//         rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
//       } else {
//         rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
//       }

//       if (rotation == null) return null;

//       // Get image format
//       final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
//       if (format == null) return null;

//       // Combine all plane bytes
//       final WriteBuffer allBytes = WriteBuffer();
//       for (final Plane plane in cameraImage.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       // Create metadata
//       final metadata = InputImageMetadata(
//         size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
//         rotation: rotation,
//         format: format,
//         bytesPerRow: cameraImage.planes.first.bytesPerRow,
//       );

//       return InputImage.fromBytes(bytes: bytes, metadata: metadata);
//     } catch (e) {
//       debugPrint('Error converting camera image: $e');
//       return null;
//     }
//   }

//   Future<void> _checkLivenessStep(Face face) async {
//     if (_currentStepIndex >= _livenessSteps.length) {
//       await _completeVerification();
//       return;
//     }

//     final currentStep = _livenessSteps[_currentStepIndex];
//     bool stepPassed = false;

//     switch (currentStep.type) {
//       case LivenessType.lookStraight:
//         stepPassed = _checkLookingStraight(face);
//         break;
//       case LivenessType.blink:
//         stepPassed = _checkBlink(face);
//         break;
//       case LivenessType.smile:
//         stepPassed = _checkSmile(face);
//         break;
//       case LivenessType.turnLeft:
//         stepPassed = _checkTurnLeft(face);
//         break;
//       case LivenessType.turnRight:
//         stepPassed = _checkTurnRight(face);
//         break;
//     }

//     if (stepPassed) {
//       if (mounted) {
//         setState(() {
//           _currentStepIndex++;
//           if (_currentStepIndex < _livenessSteps.length) {
//             _instruction = _livenessSteps[_currentStepIndex].instruction;
//           }

//           // Reset blink detection for next blink step
//           if (currentStep.type == LivenessType.blink) {
//             _blinkDetected = false;
//             _wasEyesOpen = false;
//           }
//         });
//       }

//       // Small delay before next step
//       await Future.delayed(Duration(milliseconds: 500));
//     } else {
//       if (mounted) {
//         setState(() {
//           _instruction = currentStep.instruction;
//         });
//       }
//     }
//   }

//   bool _checkLookingStraight(Face face) {
//     final headY = face.headEulerAngleY ?? 0;
//     final headZ = face.headEulerAngleZ ?? 0;
//     return headY.abs() < 10 && headZ.abs() < 10;
//   }

//   bool _checkBlink(Face face) {
//     final leftEye = face.leftEyeOpenProbability;
//     final rightEye = face.rightEyeOpenProbability;

//     if (leftEye != null && rightEye != null) {
//       // Check if eyes are open
//       bool eyesOpen = leftEye > 0.5 && rightEye > 0.5;
//       // Check if eyes are closed
//       bool eyesClosed = leftEye < 0.3 && rightEye < 0.3;

//       // Detect blink sequence: open -> closed -> detected
//       if (!_blinkDetected) {
//         if (eyesOpen) {
//           _wasEyesOpen = true;
//         } else if (eyesClosed && _wasEyesOpen) {
//           _blinkDetected = true;
//           return true;
//         }
//       }
//     }
//     return false;
//   }

//   bool _checkSmile(Face face) {
//     final smileProbability = face.smilingProbability;
//     return smileProbability != null && smileProbability > 0.7;
//   }

//   bool _checkTurnLeft(Face face) {
//     final headY = face.headEulerAngleY ?? 0;
//     return headY > 15 && headY < 35;
//   }

//   bool _checkTurnRight(Face face) {
//     final headY = face.headEulerAngleY ?? 0;
//     return headY < -15 && headY > -35;
//   }

//   Future<void> _completeVerification() async {
//     if (mounted) {
//       setState(() {
//         _verificationComplete = true;
//         _instruction = "Verification successful!";
//       });
//     }

//     await _cameraController?.stopImageStream();

//     // Capture final image for verification
//     final image = await _cameraController?.takePicture();

//     // Navigate to result screen or process verification
//     if (mounted) {
//       Future.delayed(Duration(seconds: 2), () {
//         if (mounted) {
//           Navigator.pop(context, {'success': true, 'imagePath': image?.path});
//         }
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _cameraController?.dispose();
//     _faceDetector?.close();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: SafeArea(
//         child: Stack(
//           children: [
//             // Camera preview
//             if (_isCameraInitialized && _cameraController != null)
//               Positioned.fill(child: CameraPreview(_cameraController!)),

//             // Loading indicator
//             if (!_isCameraInitialized) Center(child: CircularProgressIndicator(color: Colors.white)),

//             // Face overlay guide
//             Positioned.fill(
//               child: CustomPaint(
//                 painter: FaceOverlayPainter(faceDetected: _faceInFrame, verificationComplete: _verificationComplete),
//               ),
//             ),

//             // Top instruction bar
//             Positioned(
//               top: 20,
//               left: 20,
//               right: 20,
//               child: Container(
//                 padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.7),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Column(
//                   children: [
//                     Text(
//                       _instruction,
//                       style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
//                       textAlign: TextAlign.center,
//                     ),
//                     SizedBox(height: 10),
//                     LinearProgressIndicator(
//                       value: _livenessSteps.isEmpty ? 0 : _currentStepIndex / _livenessSteps.length,
//                       backgroundColor: Colors.white30,
//                       valueColor: AlwaysStoppedAnimation<Color>(_verificationComplete ? Colors.green : Colors.blue),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             // Bottom close button
//             Positioned(
//               bottom: 40,
//               left: 0,
//               right: 0,
//               child: Center(
//                 child: IconButton(
//                   icon: Icon(Icons.close, color: Colors.white, size: 40),
//                   onPressed: () => Navigator.pop(context),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // Custom painter for face guide overlay
// class FaceOverlayPainter extends CustomPainter {
//   final bool faceDetected;
//   final bool verificationComplete;

//   FaceOverlayPainter({required this.faceDetected, required this.verificationComplete});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 4.0;

//     if (verificationComplete) {
//       paint.color = Colors.green;
//     } else if (faceDetected) {
//       paint.color = Colors.blue;
//     } else {
//       paint.color = Colors.white.withOpacity(0.5);
//     }

//     // Draw oval face guide
//     final center = Offset(size.width / 2, size.height / 2);
//     final ovalWidth = size.width * 0.7;
//     final ovalHeight = size.height * 0.5;

//     final rect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

//     canvas.drawOval(rect, paint);

//     // Draw corner indicators
//     final cornerPaint = Paint()
//       ..color = paint.color
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 6.0;

//     final cornerLength = 30.0;

//     // Top-left
//     canvas.drawLine(Offset(rect.left, rect.top + cornerLength), Offset(rect.left, rect.top), cornerPaint);
//     canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + cornerLength, rect.top), cornerPaint);

//     // Top-right
//     canvas.drawLine(Offset(rect.right - cornerLength, rect.top), Offset(rect.right, rect.top), cornerPaint);
//     canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerLength), cornerPaint);

//     // Bottom-left
//     canvas.drawLine(Offset(rect.left, rect.bottom - cornerLength), Offset(rect.left, rect.bottom), cornerPaint);
//     canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + cornerLength, rect.bottom), cornerPaint);

//     // Bottom-right
//     canvas.drawLine(Offset(rect.right - cornerLength, rect.bottom), Offset(rect.right, rect.bottom), cornerPaint);
//     canvas.drawLine(Offset(rect.right, rect.bottom - cornerLength), Offset(rect.right, rect.bottom), cornerPaint);
//   }

//   @override
//   bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
//     return faceDetected != oldDelegate.faceDetected || verificationComplete != oldDelegate.verificationComplete;
//   }
// }

// // Liveness detection step model
// enum LivenessType { lookStraight, blink, smile, turnLeft, turnRight }

// class LivenessStep {
//   final LivenessType type;
//   final String instruction;
//   final Duration duration;

//   LivenessStep({required this.type, required this.instruction, required this.duration});
// }
