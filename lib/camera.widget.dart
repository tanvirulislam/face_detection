import 'package:camera/camera.dart';
import 'package:face_detection/enum.dart';
import 'package:face_detection/face.rules.dart';
import 'package:face_detection/channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

late List<CameraDescription> cameras;

class CameraWidget extends ConsumerStatefulWidget {
  const CameraWidget({super.key, required this.faceType});
  final FaceType faceType;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends ConsumerState<CameraWidget> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  XFile? imageFile;
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _availableCameras = await availableCameras();
    if (_availableCameras.isEmpty) return;

    if (!mounted) return;

    // Find camera with preferred direction
    final preferredCameraIndex = _availableCameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    // If preferred camera found, use it; otherwise use first available
    if (preferredCameraIndex != -1) {
      _currentCameraIndex = preferredCameraIndex;
    }

    _controller = CameraController(_availableCameras[_currentCameraIndex], ResolutionPreset.medium, enableAudio: false);

    _initializeControllerFuture = _controller!.initialize().then((_) {
      // Set flash mode from provider after initialization
      final flashMode = CameraLensDirection.front == _availableCameras[_currentCameraIndex].lensDirection
          ? FlashMode.auto
          : FlashMode.off;
      _controller!.setFlashMode(flashMode);
    });
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2) return;

    // Dispose current controller
    await _controller?.dispose();

    // Get current camera direction
    final currentDirection = _availableCameras[_currentCameraIndex].lensDirection;

    // Toggle between front and back only
    final targetDirection = currentDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    // Find camera with target direction
    final targetIndex = _availableCameras.indexWhere((camera) => camera.lensDirection == targetDirection);

    // If target camera found, use it; otherwise cycle normally
    if (targetIndex != -1) {
      _currentCameraIndex = targetIndex;
    } else {
      _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    }

    // Initialize new camera
    _controller = CameraController(_availableCameras[_currentCameraIndex], ResolutionPreset.medium, enableAudio: false);

    _initializeControllerFuture = _controller!.initialize().then((_) {});
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _cameraPreviewWidget() {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return CameraPreview(_controller!);
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  void _showResultDialog(String message) {
    final isSuccess = message.startsWith('✅');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(isSuccess ? Icons.check_circle : Icons.error, color: isSuccess ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Text(isSuccess ? 'Success' : 'Error'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // if (isSuccess) {
                //   Navigator.of(context).pop(imageFile); // Return to previous screen with image
                // }
              },
              child: Text(isSuccess ? 'OK' : 'Retry'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  color: Colors.black,
                  child: _cameraPreviewWidget(),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.bottomCenter,
                color: Colors.black,
                child: Row(
                  children: [
                    Expanded(child: SizedBox.shrink()),
                    Expanded(child: _captureButton()),
                    if (_availableCameras.length > 1) ...[
                      Expanded(
                        child: IconButton(
                          onPressed: _toggleCamera,
                          icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
                        ),
                      ),
                    ] else ...[
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  InkWell _captureButton() {
    return InkWell(
      onTap: _isProcessing
          ? null
          : () {
              _controller != null && _controller!.value.isInitialized && !_controller!.value.isRecordingVideo
                  ? onTakePictureButtonPressed()
                  : null;
            },
      child: Container(
        alignment: Alignment.center,
        height: 60,
        width: 60,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _isProcessing ? Colors.grey : Colors.white),
      ),
    );
  }

  void showInSnackBar(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> onTakePictureButtonPressed() async {
    setState(() => _isProcessing = true);

    final file = await takePicture();

    if (file == null) {
      setState(() => _isProcessing = false);
      _showResultDialog('❌ Capture failed');
      return;
    }

    final isFrontCamera = _availableCameras[_currentCameraIndex].lensDirection == CameraLensDirection.front;

    // Call your face validation here
    final result = await Chnannel.analyzeFace(file.path);
    final error = FaceRules.validate(result, expectedFace: widget.faceType, isFrontCamera: isFrontCamera);

    setState(() => _isProcessing = false);

    final message = error ?? '✅ Face validation success';
    _showResultDialog(message);
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();

      // Generate filename with current datetime
      final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String newFileName = 'image_$timestamp.jpeg';

      // For web, you need to create a new XFile with the proper name
      final XFile renamedFile = XFile(
        file.path,
        name: newFileName,
        bytes: await file.readAsBytes(), // Important for web
      );

      setState(() => imageFile = renamedFile);
      return renamedFile;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

String instruction(CameraWidget widget) {
  switch (widget.faceType) {
    case FaceType.front:
      return 'Look straight at the camera';
    case FaceType.left:
      return 'Turn your face to the left';
    case FaceType.right:
      return 'Turn your face to the right';
  }
}
