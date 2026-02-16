import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'services.dart';
import 'widgets.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.faceType});
  final FaceType faceType;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isStreaming = false;
  bool _isAnalyzing = false;
  bool _isCapturing = false;
  int _frameCount = 0;
  bool _controllerReady = false;

  late final FaceDetector _faceDetector;
  late final ImageLabeler _imageLabeler;
  final FaceGuard _faceGuard = FaceGuard();
  final BlinkDetector _blinkDetector = BlinkDetector();
  final BrightnessChecker _brightnessChecker = BrightnessChecker();

  int _labelFrame = 0;
  List<ImageLabel> _lastLabels = [];

  int _stepIndex = 0;
  bool _stepCooldown = false;
  bool _faceDetected = false;

  static const int _straightRequiredMs = 1500;
  int _straightHeldMs = 0;
  DateTime? _lastFrameTime;

  // CAPTURED IMAGES
  XFile? _frontImage;
  XFile? _leftImage;
  XFile? _rightImage;

  FaceGuardResult _guardResult = FaceGuardResult.ok;
  FaceGuardResult _lightingResult = FaceGuardResult.ok;
  String _statusText = 'Preparing camera…';
  int _feedbackSeq = 0;
  Color _ovalColor = Colors.white54;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _checkCtrl;
  late Animation<double> _check;

  StepConfig get _step => kSteps[_stepIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
      ),
    );

    _imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.035,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _check = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);

    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    final fi = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _cameraIndex = fi != -1 ? fi : 0;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    if (mounted) setState(() => _controllerReady = false);

    final old = _controller;
    _controller = null;

    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }

    _isStreaming = false;

    if (!mounted) return;

    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    _controller = controller;

    try {
      await controller.initialize();
    } catch (e) {
      dev.log('Camera init error: $e');
      return;
    }

    if (!mounted || _controller != controller) return;

    await controller.setFlashMode(FlashMode.off);

    _controllerReady = true;
    setState(() {
      _statusText = kSteps[0].instruction;
      _feedbackSeq++;
    });

    _startStream();
  }

  void _startStream() {
    if (_isStreaming || _controller == null || !_controllerReady) return;
    _isStreaming = true;

    _controller!.startImageStream((CameraImage image) async {
      _frameCount++;
      if (_step.step != LiveStep.blinkEyes && _frameCount % 4 != 0) return;
      if (_isAnalyzing || _isCapturing || _stepCooldown) return;

      _isAnalyzing = true;
      try {
        await _processFrame(image);
      } finally {
        _isAnalyzing = false;
      }
    });
  }

  Future<void> _stopStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
  }

  Future<void> _processFrame(CameraImage image) async {
    if (!mounted || !_controllerReady) return;

    try {
      // CHECK BRIGHTNESS FIRST
      final lightingCheck = _brightnessChecker.checkLighting(image);
      setState(() => _lightingResult = lightingCheck);

      final cam = _cameras[_cameraIndex];
      final isFront = cam.lensDirection == CameraLensDirection.front;
      final input = CameraUtils.toInputImage(image, cam);
      if (input == null) return;

      final faces = await _faceDetector.processImage(input);

      _labelFrame++;
      if (_labelFrame == 1 || _labelFrame % 10 == 0) {
        _lastLabels = await _imageLabeler.processImage(input);
        if (_lastLabels.isNotEmpty) {
          dev.log('🏷 ${_lastLabels.map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').join(', ')}');
        }
      }

      if (!mounted) return;

      if (faces.isEmpty) {
        _setFeedback('No face detected — center your face', Colors.red, false);
        setState(() => _guardResult = FaceGuardResult.ok);
        return;
      }

      if (faces.length > 1) {
        _setFeedback('Only one person allowed in frame', Colors.orange, false);
        return;
      }

      final face = faces.first;
      final nose = face.landmarks[FaceLandmarkType.noseBase];
      final mouthL = face.landmarks[FaceLandmarkType.leftMouth];
      final mouthR = face.landmarks[FaceLandmarkType.rightMouth];

      final guard = _faceGuard.check(
        face: face,
        labels: _lastLabels,
        hasNose: nose != null,
        hasMouth: mouthL != null && mouthR != null,
      );

      setState(() => _guardResult = guard);

      if (guard.blockStep) {
        _setFeedback(guard.message, Colors.red, true);
        return;
      }

      if (nose == null || mouthL == null || mouthR == null) {
        _setFeedback('Keep your full face in the oval', Colors.orange, true);
        return;
      }

      setState(() => _faceDetected = true);

      // Face containment check
      final screenSize = MediaQuery.of(context).size;
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();

      final bool isPortrait = screenSize.height > screenSize.width;
      final bool shouldSwap = Platform.isIOS && isPortrait && imgW > imgH;
      final double effectiveImgW = shouldSwap ? imgH : imgW;
      final double effectiveImgH = shouldSwap ? imgW : imgH;

      final double coverScale = [
        screenSize.width / effectiveImgW,
        screenSize.height / effectiveImgH,
      ].reduce((a, b) => a > b ? a : b);

      final double scaledImgW = effectiveImgW * coverScale;
      final double scaledImgH = effectiveImgH * coverScale;
      final double offsetX = (scaledImgW - screenSize.width) / 2;
      final double offsetY = (scaledImgH - screenSize.height) / 2;

      final faceBox = face.boundingBox;

      double faceLeft = faceBox.left * coverScale - offsetX;
      double faceRight = faceBox.right * coverScale - offsetX;
      double faceTop = faceBox.top * coverScale - offsetY;
      double faceBottom = faceBox.bottom * coverScale - offsetY;

      if (isFront) {
        final double mirroredLeft = screenSize.width - faceRight;
        final double mirroredRight = screenSize.width - faceLeft;
        faceLeft = mirroredLeft;
        faceRight = mirroredRight;
      }

      final Rect faceScreenRect = Rect.fromLTRB(faceLeft, faceTop, faceRight, faceBottom);
      final Rect oval = OvalUtils.ovalRect(screenSize);

      final Rect intersection = faceScreenRect.intersect(oval);
      final double faceArea = faceScreenRect.width * faceScreenRect.height;
      final double iof = faceArea > 0
          ? (intersection.width.clamp(0.0, double.infinity) * intersection.height.clamp(0.0, double.infinity)) /
                faceArea
          : 0.0;

      dev.log('📐 IoF=${iof.toStringAsFixed(2)}');

      if (iof < 0.75) {
        String hint = 'Move your face into the oval';
        if (faceScreenRect.center.dy < oval.top + oval.height * 0.25) {
          hint = '⬇️ Move your face down';
        } else if (faceScreenRect.center.dy > oval.bottom - oval.height * 0.25) {
          hint = '⬆️ Move your face up';
        } else if (faceScreenRect.center.dx < oval.left + oval.width * 0.25) {
          hint = '➡️ Move your face right';
        } else if (faceScreenRect.center.dx > oval.right - oval.width * 0.25) {
          hint = '⬅️ Move your face left';
        } else if (faceScreenRect.height > oval.height * 1.1) {
          hint = '🔙 Move further from camera';
        } else if (faceScreenRect.height < oval.height * 0.55) {
          hint = '🔜 Move closer to camera';
        }
        _setFeedback(hint, Colors.orange, true);
        return;
      }

      double yaw = face.headEulerAngleY ?? 0;
      if (isFront) yaw = -yaw;

      _evaluate(face: face, yaw: yaw, smile: face.smilingProbability ?? 0.0);
    } catch (e) {
      dev.log('Frame error: $e');
    }
  }

  void _evaluate({required Face face, required double yaw, required double smile}) {
    // ⚠️ CHECK LIGHTING FIRST - BEFORE ANY STEP EVALUATION
    if (_lightingResult.blockStep) {
      // Don't allow any step to pass if lighting is blocked
      return;
    }

    bool passed = false;

    switch (_step.step) {
      case LiveStep.lookStraight:
        final now = DateTime.now();
        final frameGapMs = _lastFrameTime != null ? now.difference(_lastFrameTime!).inMilliseconds : 0;
        _lastFrameTime = now;

        if (yaw.abs() < 12) {
          _straightHeldMs += frameGapMs.clamp(0, 200);
        } else {
          _straightHeldMs = 0;
          _setFeedback('Look straight at the camera', _step.color, true);
          break;
        }

        if (_straightHeldMs >= _straightRequiredMs) {
          passed = true;
        } else {
          final remaining = ((_straightRequiredMs - _straightHeldMs) / 1000.0).ceil().clamp(
            1,
            (_straightRequiredMs / 1000).ceil(),
          );
          _setFeedback('Hold still… ${remaining}s', _step.color, true);
        }
        break;

      case LiveStep.blinkEyes:
        _blinkDetector.update(face.leftEyeOpenProbability, face.rightEyeOpenProbability);
        passed = _blinkDetector.blinkCount >= 2;
        if (!passed) {
          final c = _blinkDetector.blinkCount;
          _setFeedback(c == 0 ? 'Blink slowly and naturally' : 'Good! One more… $c / 2', _step.color, true);
        }
        break;

      case LiveStep.turnLeft:
        passed = yaw > 22;
        if (!passed) {
          _setFeedback('Turn head more to the LEFT ⬅️', _step.color, true);
        }
        break;

      case LiveStep.turnRight:
        passed = yaw < -22;
        if (!passed) {
          _setFeedback('Turn head more to the RIGHT ➡️', _step.color, true);
        }
        break;

      case LiveStep.smile:
        passed = smile > 0.75;
        if (!passed) {
          _setFeedback('Smile a little more 😊', _step.color, true);
        }
        break;
    }

    if (passed) _onPassed();
  }

  void _onPassed() {
    _setFeedback('✓ Done!', Colors.green, true);
    _checkCtrl.forward(from: 0);
    _stepCooldown = true;
    _blinkDetector.reset();
    _straightHeldMs = 0;
    _lastFrameTime = null;

    Future.delayed(const Duration(milliseconds: 700), () async {
      if (!mounted) return;

      // CAPTURE IMAGES FOR SPECIFIC STEPS
      if (_step.step == LiveStep.lookStraight || _step.step == LiveStep.turnLeft || _step.step == LiveStep.turnRight) {
        await _captureStepImage();
      }

      if (_stepIndex < kSteps.length - 1) {
        setState(() {
          _stepIndex++;
          _statusText = kSteps[_stepIndex].instruction;
          _ovalColor = kSteps[_stepIndex].color;
          _feedbackSeq++;
        });
        _stepCooldown = false;
      } else {
        _finishVerification();
      }
    });
  }

  Future<void> _captureStepImage() async {
    if (_isCapturing) return;
    _isCapturing = true;

    try {
      await _stopStream();
      await Future.delayed(const Duration(milliseconds: 100));

      final file = await _controller!.takePicture();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final bytes = await file.readAsBytes();

      if (_step.step == LiveStep.lookStraight) {
        _frontImage = XFile(file.path, name: 'front_$ts.jpeg', bytes: bytes);
        dev.log('📸 Front image captured');
      } else if (_step.step == LiveStep.turnLeft) {
        _leftImage = XFile(file.path, name: 'left_$ts.jpeg', bytes: bytes);
        dev.log('📸 Left image captured');
      } else if (_step.step == LiveStep.turnRight) {
        _rightImage = XFile(file.path, name: 'right_$ts.jpeg', bytes: bytes);
        dev.log('📸 Right image captured');
      }

      await Future.delayed(const Duration(milliseconds: 200));
      _startStream();
    } catch (e) {
      dev.log('Step capture error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _finishVerification() async {
    _setFeedback('✅ Verification Complete!', Colors.green, true);

    setState(() {
      _statusText = '✅ Verified!';
      _ovalColor = Colors.green;
      _feedbackSeq++;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    if (mounted && _frontImage != null && _leftImage != null && _rightImage != null) {
      final result = VerificationResult(frontImage: _frontImage!, leftImage: _leftImage!, rightImage: _rightImage!);
      Navigator.pop(context, result);
    } else {
      dev.log('⚠️ Missing images: front=$_frontImage, left=$_leftImage, right=$_rightImage');
      Navigator.pop(context);
    }
  }

  void _setFeedback(String text, Color color, bool detected) {
    if (!mounted) return;
    setState(() {
      _statusText = text;
      _ovalColor = color;
      _faceDetected = detected;
      _feedbackSeq++;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _controllerReady = false);
      _stopStream();
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    _controllerReady = false;
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    _checkCtrl.dispose();
    _faceDetector.close();
    _imageLabeler.close();
    _stopStream();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller != null && _controllerReady;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ready ? _buildBody() : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildBody() {
    final size = MediaQuery.of(context).size;

    // Determine which warning to show (priority: guard > lighting)
    final activeWarning = _guardResult.blockStep ? _guardResult : _lightingResult;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera Preview
        CameraPreview(_controller!),

        // Oval with pulse animation
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => CustomPaint(
            painter: OvalPainter(
              color: _guardResult.blockStep
                  ? Colors.red
                  : _lightingResult.warning == FaceWarning.lowLight
                  ? Colors.orange
                  : _ovalColor,
              scale: _pulse.value,
            ),
            child: const SizedBox.expand(),
          ),
        ),

        // Face alignment hint
        if (!_faceDetected)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final oval = OvalUtils.ovalRect(size);
                return Stack(
                  children: [
                    Positioned(
                      top: oval.bottom + 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: const Text(
                            'Align your full face inside the oval',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // Close button
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),

        // Step progress indicator
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, left: 64, right: 20),
              child: StepProgressIndicator(currentStep: _stepIndex, steps: kSteps),
            ),
          ),
        ),

        // Warning banner (Guard or Lighting)
        if (activeWarning.warning != FaceWarning.none)
          Positioned(
            top: 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (activeWarning.blockStep ? Colors.red : Colors.orange).withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    activeWarning.warning == FaceWarning.lowLight
                        ? Icons.lightbulb_outline
                        : activeWarning.warning == FaceWarning.sunglasses
                        ? Icons.wb_sunny_outlined
                        : activeWarning.warning == FaceWarning.eyeglasses
                        ? Icons.visibility_outlined
                        : Icons.warning_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      activeWarning.message,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Step icon indicator
        Positioned(
          top: size.height * 0.17,
          left: 0,
          right: 0,
          child: Center(
            child: ScaleTransition(
              scale: _check,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _step.color.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _step.color.withOpacity(0.4), blurRadius: 14)],
                ),
                child: Icon(_step.icon, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),

        // Bottom sheet content
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 44),
            decoration: const BoxDecoration(
              color: Color(0xE8000000),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                Text(
                  'Step ${_stepIndex + 1} of ${kSteps.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _statusText,
                    key: ValueKey('$_feedbackSeq:$_statusText'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _guardResult.blockStep || !_faceDetected ? Colors.redAccent : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_step.step == LiveStep.lookStraight) ...[
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_straightHeldMs / _straightRequiredMs).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(_step.color),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_step.step == LiveStep.blinkEyes) ...[
                  BlinkIndicator(blinkCount: _blinkDetector.blinkCount),
                  const SizedBox(height: 14),
                ],
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _faceDetected ? Colors.green : Colors.redAccent),
                    color: (_faceDetected ? Colors.green : Colors.red).withOpacity(0.12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _faceDetected ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: _faceDetected ? Colors.green : Colors.orange,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _faceDetected ? 'Face detected' : 'No face detected',
                        style: TextStyle(color: _faceDetected ? Colors.green : Colors.orange, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
