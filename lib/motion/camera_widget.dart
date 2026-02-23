import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:face_detection/motion/captured_image_validation.dart';
import 'package:face_detection/motion/save_photo_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:intl/intl.dart';

// import 'capture_validator.dart';
import 'models.dart';
import 'services.dart';
import 'widgets.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, required this.faceType});
  final FaceType faceType;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isStreaming = false;
  bool _isAnalyzing = false;
  bool _isCapturing = false;
  int _frameCount = 0;
  bool _controllerReady = false;
  double _lastLeftEyeProb = 1.0;
  double _lastRightEyeProb = 1.0;
  bool _eyesClosedWarning = false;
  bool _showCaptureLoader = false;
  double _captureProgress = 0.0;

  // Validation state
  bool _showValidationResult = false;
  bool _validationPassed = false;
  String _validationMessage = '';
  FaceWarning _validationWarning = FaceWarning.none;
  int _validationRetryCount = 0;
  static const int _maxValidationRetries = 3;

  int _eyeOpenRetryCount = 0;
  static const int _maxEyeOpenRetries = 5;

  late final FaceDetector _faceDetector;
  late final ImageLabeler _imageLabeler;
  late final CapturedImageValidator _captureValidator;

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
        performanceMode: Platform.isAndroid ? FaceDetectorMode.accurate : FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
      ),
    );

    _imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
    _captureValidator = CapturedImageValidator();

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
    _isStreaming = false;

    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }

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

    try {
      _controller!.startImageStream((CameraImage image) async {
        _frameCount++;
        if (_step.step != LiveStep.blinkEyes) {
          if (Platform.isAndroid && _frameCount % 3 != 0) return;
          if (!Platform.isAndroid && _frameCount % 4 != 0) return;
        }
        if (_isAnalyzing || _isCapturing || _stepCooldown) return;
        _isAnalyzing = true;
        try {
          await _processFrame(image);
        } finally {
          _isAnalyzing = false;
        }
      });
    } catch (e) {
      dev.log('startImageStream failed — reinitializing camera: $e');
      _isStreaming = false;
      Future.microtask(() async {
        if (mounted) await _startCamera();
      });
    }
  }

  Future<void> _stopStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}
  }

  Future<void> _processFrame(CameraImage image) async {
    if (!mounted || !_controllerReady) return;

    try {
      final lightingCheck = _brightnessChecker.checkLighting(image);
      setState(() => _lightingResult = lightingCheck);

      final cam = _cameras[_cameraIndex];
      final isFront = cam.lensDirection == CameraLensDirection.front;
      final input = CameraUtils.toInputImage(image, cam);
      if (input == null) return;

      final faces = await _faceDetector.processImage(input);

      _labelFrame++;
      if (_labelFrame == 1 || _labelFrame % 10 == 0) {
        InputImage labelerInput = input;
        if (Platform.isAndroid) {
          final format = InputImageFormatValue.fromRawValue(image.format.raw);
          if (format != null) {
            final WriteBuffer allBytes = WriteBuffer();
            for (final plane in image.planes) {
              allBytes.putUint8List(plane.bytes);
            }
            labelerInput = InputImage.fromBytes(
              bytes: allBytes.done().buffer.asUint8List(),
              metadata: InputImageMetadata(
                size: Size(image.width.toDouble(), image.height.toDouble()),
                rotation: InputImageRotation.rotation0deg,
                format: format,
                bytesPerRow: image.planes[0].bytesPerRow,
              ),
            );
          }
        }
        _lastLabels = await _imageLabeler.processImage(labelerInput);
        if (_lastLabels.isNotEmpty) {
          dev.log('🏷 ${_lastLabels.map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').join(', ')}');
        }
      }

      if (!mounted) return;

      if (faces.isEmpty) {
        if (Platform.isAndroid) {
          if (!_faceDetected) _setFeedback('Move your face into the camera', Colors.red, false);
        } else {
          _setFeedback('Move your face into the camera', Colors.red, false);
        }
        if (_eyesClosedWarning) setState(() => _eyesClosedWarning = false);
        setState(() => _guardResult = FaceGuardResult.ok);
        return;
      }

      if (faces.length > 1) {
        _setFeedback('Only one person allowed in frame', Colors.orange, false);
        return;
      }

      final face = faces.first;

      if (face.leftEyeOpenProbability != null) _lastLeftEyeProb = face.leftEyeOpenProbability!;
      if (face.rightEyeOpenProbability != null) _lastRightEyeProb = face.rightEyeOpenProbability!;

      if (_step.step == LiveStep.lookStraight) {
        final eyeClosedThresh = Platform.isAndroid ? 0.35 : 0.4;
        final eyesClosed = _lastLeftEyeProb < eyeClosedThresh || _lastRightEyeProb < eyeClosedThresh;
        if (eyesClosed != _eyesClosedWarning) setState(() => _eyesClosedWarning = eyesClosed);
      } else {
        if (_eyesClosedWarning) setState(() => _eyesClosedWarning = false);
      }

      final nose = face.landmarks[FaceLandmarkType.noseBase];
      final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth];
      final mouthRight = face.landmarks[FaceLandmarkType.rightMouth];
      final hasNose = nose != null;
      final hasMouth = mouthLeft != null || mouthRight != null;

      double yaw = face.headEulerAngleY ?? 0;
      if (isFront) yaw = -yaw;

      final screenSize = MediaQuery.of(context).size;
      final imgW = image.width.toDouble();
      final imgH = image.height.toDouble();

      final bool isPortrait = screenSize.height > screenSize.width;
      final bool shouldSwap = isPortrait && imgW > imgH;
      final double effectiveImgW = shouldSwap ? imgH : imgW;
      final double effectiveImgH = shouldSwap ? imgW : imgH;

      double inputWidth, inputHeight;
      if (Platform.isAndroid) {
        inputWidth = imgH;
        inputHeight = imgW;
      } else {
        inputWidth = imgW;
        inputHeight = imgH;
      }

      final double coverScale = [
        screenSize.width / inputWidth,
        screenSize.height / inputHeight,
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
        final double mirroredLeft = screenSize.width - (faceBox.right * coverScale - offsetX);
        final double mirroredRight = screenSize.width - (faceBox.left * coverScale - offsetX);
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

      final guard = _faceGuard.check(
        face: face,
        labels: _lastLabels,
        hasNose: hasNose,
        hasMouth: hasMouth,
        yaw: yaw,
        faceInOval: iof >= 0.75,
      );

      setState(() => _guardResult = guard);

      if (guard.blockStep) {
        _setFeedback(guard.message, Colors.red, true);
        return;
      }

      setState(() => _faceDetected = true);

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

      dev.log('🎯 yaw=$yaw iof=${iof.toStringAsFixed(2)} smile=${face.smilingProbability?.toStringAsFixed(2)}');
      _evaluate(face: face, yaw: yaw, smile: face.smilingProbability ?? 0.0);
    } catch (e) {
      dev.log('Frame error: $e');
    }
  }

  void _evaluate({required Face face, required double yaw, required double smile}) {
    dev.log(
      '🔍 evaluate: step=${_step.step} yaw=$yaw lightingBlock=${_lightingResult.blockStep} cooldown=$_stepCooldown',
    );

    if (_lightingResult.blockStep) return;

    bool passed = false;

    switch (_step.step) {
      case LiveStep.lookStraight:
        final now = DateTime.now();
        final frameGapMs = _lastFrameTime != null ? now.difference(_lastFrameTime!).inMilliseconds : 0;
        _lastFrameTime = now;

        if (_eyesClosedWarning) {
          _setFeedback('Keep your eyes open! 👀', Colors.orange, true);
          break;
        }

        if (smile < 0.30) {
          _straightHeldMs = 0;
          _setFeedback('Please smile 😊', _step.color, true);
          break;
        }

        if (yaw.abs() < 20) {
          _straightHeldMs += frameGapMs.clamp(0, Platform.isAndroid ? 300 : 200);
        } else if (Platform.isAndroid && yaw.abs() < 35) {
          // mild tilt on Android just pauses
        } else {
          _straightHeldMs = (_straightHeldMs - 200).clamp(0, _straightRequiredMs);
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
        if (yaw.abs() > 20) {
          _setFeedback('Face straight first, then blink 👀', _step.color, true);
          break;
        }
        _blinkDetector.update(face.leftEyeOpenProbability, face.rightEyeOpenProbability);
        passed = _blinkDetector.blinkCount >= 2;
        if (!passed) {
          final c = _blinkDetector.blinkCount;
          _setFeedback(c == 0 ? 'Blink slowly and naturally' : 'Good! One more… $c / 2', _step.color, true);
        }
        break;

      case LiveStep.turnLeft:
        passed = Platform.isAndroid ? yaw < -18 : yaw > 18;
        if (!passed) _setFeedback('Turn head more to the LEFT ⬅️', _step.color, true);
        break;

      case LiveStep.turnRight:
        passed = Platform.isAndroid ? yaw > 18 : yaw < -18;
        if (!passed) _setFeedback('Turn head more to the RIGHT ➡️', _step.color, true);
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

      if (_step.step == LiveStep.lookStraight || _step.step == LiveStep.turnLeft || _step.step == LiveStep.turnRight) {
        final captured = await _captureStepImage();
        if (!captured) return;
        _eyeOpenRetryCount = 0;
        setState(() => _eyesClosedWarning = false);
      }

      if (_stepIndex < kSteps.length - 1) {
        setState(() {
          _stepIndex++;
          _statusText = kSteps[_stepIndex].instruction;
          _ovalColor = kSteps[_stepIndex].color;
          _feedbackSeq++;
          _validationRetryCount = 0; // reset retry count for new step
        });
        _stepCooldown = false;
      } else {
        _finishVerification();
      }
    });
  }

  // ─────────────────────────────────────────────────────────
  // CAPTURE + VALIDATE
  // ─────────────────────────────────────────────────────────

  Future<bool> _captureStepImage() async {
    if (_isCapturing) return false;

    // Eyes check (lookStraight only)
    if (_step.step == LiveStep.lookStraight) {
      final captureEyeThresh = Platform.isAndroid ? 0.35 : 0.5;
      if (_lastLeftEyeProb < captureEyeThresh || _lastRightEyeProb < captureEyeThresh) {
        _eyeOpenRetryCount++;
        if (_eyeOpenRetryCount >= _maxEyeOpenRetries) {
          _eyeOpenRetryCount = 0;
        } else {
          _straightHeldMs = 0;
          _lastFrameTime = null;
          _stepCooldown = false;
          setState(() => _eyesClosedWarning = true);
          _setFeedback('Keep your eyes open! 👀', Colors.orange, true);
          return false;
        }
      } else {
        _eyeOpenRetryCount = 0;
        setState(() => _eyesClosedWarning = false);
      }
    }

    _isCapturing = true;

    try {
      // Stop stream before capturing
      if (_isStreaming) {
        _isStreaming = false;
        try {
          if (_controller != null && _controller!.value.isStreamingImages) {
            await _controller!.stopImageStream();
          }
        } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 200));

      if (_controller == null || !_controllerReady) return false;

      // ── CAPTURE ──
      final file = await _controller!.takePicture();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final bytes = await file.readAsBytes();
      final capturedFile = XFile(file.path, name: '${_step.step.name}_$ts.jpeg', bytes: bytes);

      // ── SHOW progress loader ──
      setState(() {
        _showCaptureLoader = true;
        _captureProgress = 0.0;
      });

      await _animateCaptureProgress(0.0, 0.5, const Duration(milliseconds: 300));

      // ── VALIDATE captured image (full pipeline) ──
      final screenSize = MediaQuery.of(context).size;
      final validationResult = await _captureValidator.validate(capturedFile, _step.step, screenSize);

      await _animateCaptureProgress(0.5, 1.0, const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 150));

      setState(() => _showCaptureLoader = false);

      if (!validationResult.isValid) {
        // ── Validation FAILED ──
        _validationRetryCount++;
        dev.log('❌ Capture validation failed (attempt $_validationRetryCount): ${validationResult.failureReason}');

        final retryMessage = _validationRetryCount >= _maxValidationRetries
            ? '⚠️ Please try again carefully'
            : '❌ Wrong pose captured — ${validationResult.failureReason ?? "Try again"}';

        // Show failure banner briefly
        await _showValidationBanner(
          passed: false,
          message: retryMessage,
          warning: validationResult.warning ?? FaceWarning.none,
        );

        // Reset step so user must redo it
        await _resetCurrentStep();
        return false;
      }

      // ── Validation PASSED ──
      dev.log('✅ Capture validated: step=${_step.step} yaw=${validationResult.detectedYaw?.toStringAsFixed(1)}°');

      // Store the validated image
      if (_step.step == LiveStep.lookStraight) {
        _frontImage = capturedFile;
      } else if (_step.step == LiveStep.turnLeft) {
        _leftImage = capturedFile;
      } else if (_step.step == LiveStep.turnRight) {
        _rightImage = capturedFile;
      }

      _validationRetryCount = 0;

      // Show success banner briefly
      await _showValidationBanner(passed: true, message: '✅ Image verified!');

      // Restart stream for next step
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && _controllerReady) {
        _labelFrame = 0;
        _lastLabels = [];
        _faceGuard.reset();
        try {
          _startStream();
        } catch (e) {
          await _startCamera();
        }
      }

      return true;
    } catch (e) {
      dev.log('Step capture error: $e');
      setState(() => _showCaptureLoader = false);
      await _resetCurrentStep();
      return false;
    } finally {
      _isCapturing = false;
    }
  }

  /// Shows a brief validation result banner (pass/fail) for 1.2 seconds.
  Future<void> _showValidationBanner({
    required bool passed,
    required String message,
    FaceWarning warning = FaceWarning.none,
  }) async {
    if (!mounted) return;
    setState(() {
      _showValidationResult = true;
      _validationPassed = passed;
      _validationMessage = message;
      _validationWarning = warning;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _showValidationResult = false);
  }

  /// Resets the current step so the user must redo the pose.
  Future<void> _resetCurrentStep() async {
    if (!mounted) return;

    // Determine retry instruction
    String retryInstruction;
    switch (_step.step) {
      case LiveStep.lookStraight:
        retryInstruction = 'Look straight & smile — try again 😊';
        break;
      case LiveStep.turnLeft:
        retryInstruction = 'Turn more to the LEFT ⬅️ — try again';
        break;
      case LiveStep.turnRight:
        retryInstruction = 'Turn more to the RIGHT ➡️ — try again';
        break;
      default:
        retryInstruction = _step.instruction;
    }

    setState(() {
      _stepCooldown = false;
      _straightHeldMs = 0;
      _lastFrameTime = null;
      _statusText = retryInstruction;
      _ovalColor = _step.color;
      _feedbackSeq++;
      _faceDetected = false;
    });

    _blinkDetector.reset();
    _faceGuard.reset();
    _labelFrame = 0;
    _lastLabels = [];

    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted && _controllerReady) {
      try {
        _startStream();
      } catch (_) {
        await _startCamera();
      }
    }
  }

  Future<void> _animateCaptureProgress(double from, double to, Duration duration) async {
    final steps = 20;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final increment = (to - from) / steps;
    for (int i = 0; i < steps; i++) {
      await Future.delayed(Duration(milliseconds: stepDuration));
      if (!mounted) return;
      setState(() => _captureProgress = from + increment * (i + 1));
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
      ref.read(clickedPhotoProvider('front').notifier).setImage(_frontImage);
      ref.read(clickedPhotoProvider('left').notifier).setImage(_leftImage);
      ref.read(clickedPhotoProvider('right').notifier).setImage(_rightImage);

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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controllerReady = false;
      _isStreaming = false;
      try {
        if (_controller != null && _controller!.value.isStreamingImages) {
          _controller!.stopImageStream();
        }
      } catch (_) {}
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    _controllerReady = false;
    _isStreaming = false;
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    _checkCtrl.dispose();
    _faceDetector.close();
    _imageLabeler.close();
    _captureValidator.dispose();
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        _controller!.stopImageStream();
      }
    } catch (_) {}
    _controller?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

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

        // Eyes closed warning
        if (_eyesClosedWarning && _faceDetected)
          Positioned(
            top: activeWarning.warning != FaceWarning.none ? 140 : 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '👀 Please keep your eyes open',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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
                            '📷 Move your face into the oval',
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

        // Capture loader with validation progress
        if (_showCaptureLoader)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _captureProgress),
                        duration: const Duration(milliseconds: 80),
                        builder: (_, value, __) => CircularProgressIndicator(
                          value: value,
                          strokeWidth: 7,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _captureProgress < 0.55 ? 'Capturing…' : 'Verifying pose…',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Validation result banner ──
        if (_showValidationResult)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showValidationResult ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black45,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: _validationPassed ? Colors.green.shade700 : Colors.red.shade700,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (_validationPassed ? Colors.green : Colors.red).withOpacity(0.5),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _validationPassed
                                ? Icons.check_circle
                                : _validationWarning == FaceWarning.sunglasses
                                ? Icons.wb_sunny_outlined
                                : _validationWarning == FaceWarning.eyeglasses
                                ? Icons.visibility_outlined
                                : _validationWarning == FaceWarning.maskCovering
                                ? Icons.face_retouching_off
                                : _validationWarning == FaceWarning.lowLight
                                ? Icons.lightbulb_outline
                                : _validationWarning == FaceWarning.nudity
                                ? Icons.warning_rounded
                                : _validationWarning == FaceWarning.eyesClosed
                                ? Icons.remove_red_eye_outlined
                                : Icons.cancel,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              _validationMessage,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
