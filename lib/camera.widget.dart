import 'package:camera/camera.dart';
import 'package:face_detection/camera.service.dart';
import 'package:face_detection/face.rules.dart';
import 'package:face_detection/face.validator.dart';
import 'package:flutter/material.dart';

class CameraFacePage extends StatefulWidget {
  const CameraFacePage({super.key});

  @override
  State<CameraFacePage> createState() => _CameraFacePageState();
}

class _CameraFacePageState extends State<CameraFacePage> {
  final CameraService _cameraService = CameraService();
  bool loading = true;
  String? message;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    setState(() => loading = false);
  }

  Future<void> _captureAndValidate() async {
    setState(() => message = null);

    final file = await _cameraService.takePicture();
    if (file == null) {
      setState(() => message = 'Capture failed');
      return;
    }

    final result = await FaceValidator.analyzeFace(file.path);

    final error = FaceRules.validate(result);

    setState(() {
      message = error ?? '✅ Face validation success';
    });
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face Capture')),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_cameraService.controller)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(onPressed: _captureAndValidate, child: const Text('Capture & Validate')),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(message!, style: TextStyle(color: message!.startsWith('✅') ? Colors.green : Colors.red)),
            ),
        ],
      ),
    );
  }
}
