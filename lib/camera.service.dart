// import 'dart:io';
// import 'package:camera/camera.dart';

// class CameraService {
//   CameraController? _controller;

//   Future<void> initialize() async {
//     final cameras = await availableCameras();

//     // Prefer front camera
//     final frontCamera = cameras.firstWhere(
//       (c) => c.lensDirection == CameraLensDirection.front,
//       orElse: () => cameras.first,
//     );

//     _controller = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);

//     await _controller!.initialize();
//   }

//   CameraController get controller => _controller!;

//   Future<File?> takePicture() async {
//     if (_controller == null || !_controller!.value.isInitialized) {
//       return null;
//     }

//     final XFile file = await _controller!.takePicture();
//     return File(file.path);
//   }

//   void dispose() {
//     _controller?.dispose();
//   }
// }
