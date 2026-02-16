// import 'dart:async';
// import 'dart:developer';
// import 'dart:io';
// import 'dart:typed_data';

// import 'package:camera/camera.dart';
// import 'package:face_detection/enum.dart';
// import 'package:face_detection/faceMatcher.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
// import 'package:intl/intl.dart';

// // ─────────────────────────────────────────────
// // STEPS
// // ─────────────────────────────────────────────

// enum LiveStep { lookStraight, blinkEyes, turnLeft, turnRight, smile }

// class StepConfig {
//   final LiveStep step;
//   final String instruction;
//   final IconData icon;
//   final Color color;
//   const StepConfig(this.step, this.instruction, this.icon, this.color);
// }

// const List<StepConfig> kSteps = [
//   StepConfig(LiveStep.lookStraight, 'Look straight at the camera', Icons.face, Color(0xFF2196F3)),
//   StepConfig(LiveStep.blinkEyes, 'Blink your eyes twice', Icons.remove_red_eye, Color(0xFF9C27B0)),
//   StepConfig(LiveStep.turnLeft, 'Slowly turn head LEFT ⬅️', Icons.arrow_back, Color(0xFFFF9800)),
//   StepConfig(LiveStep.turnRight, 'Slowly turn head RIGHT ➡️', Icons.arrow_forward, Color(0xFFFF5722)),
//   StepConfig(LiveStep.smile, 'Give a natural smile 😊', Icons.sentiment_satisfied, Color(0xFF4CAF50)),
// ];

// // ─────────────────────────────────────────────
// // FACE GUARD — mask / glasses / nudity detection
// // ─────────────────────────────────────────────

// enum FaceWarning { none, maskCovering, sunglasses, eyeglasses, nudity }

// class FaceGuardResult {
//   final FaceWarning warning;
//   final String message;
//   final bool blockStep;
//   const FaceGuardResult({required this.warning, required this.message, required this.blockStep});
//   static const ok = FaceGuardResult(warning: FaceWarning.none, message: '', blockStep: false);
// }

// class FaceGuard {
//   static const int _sunglassWindow = 20;
//   static const double _sunglassMaxThresh = 0.45;

//   final List<double> _eyeMaxHistory = [];

//   static const _nudityLabels = ['nudity', 'nude', 'naked', 'underwear', 'bikini', 'swimwear', 'lingerie', 'topless'];
//   static const _maskLabels = ['mask', 'face mask', 'surgical mask', 'respirator', 'hand'];
//   // Sunglasses checked separately (blocking) before regular glasses.
//   static const _sunglassLabels = ['sunglasses', 'goggles'];
//   // Regular glasses — no longer includes sunglasses/goggles (handled above).
//   static const _glassLabels = ['glasses', 'spectacles', 'eyewear'];

//   FaceGuardResult check({
//     required Face face,
//     required List<ImageLabel> labels,
//     required bool hasNose,
//     required bool hasMouth,
//   }) {
//     for (final l in labels) {
//       if (_nudityLabels.any((n) => l.label.toLowerCase().contains(n)) && l.confidence > 0.6) {
//         log('🚫 Nudity: ${l.label} (${l.confidence.toStringAsFixed(2)})');
//         return const FaceGuardResult(
//           warning: FaceWarning.nudity,
//           message: '🚫 Nudity detected. Please dress appropriately.',
//           blockStep: true,
//         );
//       }
//     }

//     for (final l in labels) {
//       if (_maskLabels.any((m) => l.label.toLowerCase().contains(m)) && l.confidence > 0.55) {
//         log('⚠️ Mask/hand: ${l.label} (${l.confidence.toStringAsFixed(2)})');
//         return const FaceGuardResult(
//           warning: FaceWarning.maskCovering,
//           message: '⚠️ Remove mask or hand from face.',
//           blockStep: true,
//         );
//       }
//     }

//     if (!hasNose && !hasMouth) {
//       return const FaceGuardResult(
//         warning: FaceWarning.maskCovering,
//         message: '⚠️ Face appears covered. Remove mask or hand.',
//         blockStep: true,
//       );
//     }
//     if (!hasMouth && hasNose) {
//       return const FaceGuardResult(
//         warning: FaceWarning.maskCovering,
//         message: '⚠️ Remove face mask to continue.',
//         blockStep: true,
//       );
//     }

//     // ── Rolling eye-history sunglasses heuristic (kept as dark-tint fallback) ──
//     // This catches opaque/dark lenses that the image labeler may miss because
//     // they don't look like "sunglasses" to the ML model.
//     final leftEye = face.leftEyeOpenProbability ?? 1.0;
//     final rightEye = face.rightEyeOpenProbability ?? 1.0;
//     _eyeMaxHistory.add(leftEye > rightEye ? leftEye : rightEye);
//     if (_eyeMaxHistory.length > _sunglassWindow) _eyeMaxHistory.removeAt(0);

//     if (_eyeMaxHistory.length >= _sunglassWindow) {
//       final maxVal = _eyeMaxHistory.reduce((a, b) => a > b ? a : b);
//       if (maxVal < _sunglassMaxThresh) {
//         log('🕶 Dark lenses — max eye: $maxVal');
//         return const FaceGuardResult(
//           warning: FaceWarning.sunglasses,
//           message: '🕶 Remove sunglasses to continue.',
//           blockStep: true,
//         );
//       }
//     }

//     // ── Label-based glasses / sunglasses detection ───────────────────────────
//     // Check sunglasses labels first (stricter) before regular glasses.
//     // Both now block — face verification requires a clear, unobstructed view
//     // of the eyes for blink detection and liveness.
//     for (final l in labels) {
//       if (_sunglassLabels.any((s) => l.label.toLowerCase().contains(s)) && l.confidence > 0.60) {
//         log('🕶 Sunglasses label: ${l.label} (${l.confidence.toStringAsFixed(2)})');
//         return const FaceGuardResult(
//           warning: FaceWarning.sunglasses,
//           message: '🕶 Remove sunglasses to continue.',
//           blockStep: true,
//         );
//       }
//     }

//     for (final l in labels) {
//       if (_glassLabels.any((g) => l.label.toLowerCase().contains(g)) && l.confidence > 0.65) {
//         log('👓 Glasses: ${l.label} (${l.confidence.toStringAsFixed(2)})');
//         return const FaceGuardResult(
//           warning: FaceWarning.eyeglasses,
//           message: '👓 Remove glasses to continue.',
//           blockStep: true,
//         );
//       }
//     }

//     return FaceGuardResult.ok;
//   }

//   void reset() => _eyeMaxHistory.clear();
// }

// // ─────────────────────────────────────────────
// // BLINK DETECTOR
// // ─────────────────────────────────────────────

// class BlinkDetector {
//   static const double _closedThreshold = 0.35;
//   static const double _openThreshold = 0.80;
//   static const int _cooldownMs = 600;

//   int _blinkCount = 0;
//   bool _inBlink = false;
//   bool _cooldown = false;
//   DateTime? _blinkStart;

//   int get blinkCount => _blinkCount;

//   bool update(double? l, double? r) {
//     final avg = ((l ?? 1.0) + (r ?? 1.0)) / 2.0;
//     log(
//       '👁 L:${(l ?? 1).toStringAsFixed(2)} R:${(r ?? 1).toStringAsFixed(2)} avg:${avg.toStringAsFixed(2)} inBlink:$_inBlink blinks:$_blinkCount',
//     );

//     if (_cooldown) return false;

//     if (!_inBlink) {
//       if (avg < _closedThreshold) {
//         _inBlink = true;
//         _blinkStart = DateTime.now();
//       }
//     } else {
//       if (avg > _openThreshold) {
//         final ms = DateTime.now().difference(_blinkStart!).inMilliseconds;
//         if (ms < 800) {
//           _blinkCount++;
//           log('✅ Blink #$_blinkCount (${ms}ms)');
//           _cooldown = true;
//           Future.delayed(Duration(milliseconds: _cooldownMs), () => _cooldown = false);
//         } else {
//           log('⚠️ Blink rejected ${ms}ms');
//         }
//         _inBlink = false;
//         return _blinkCount > 0;
//       }
//       if (DateTime.now().difference(_blinkStart!).inMilliseconds > 1000) _inBlink = false;
//     }
//     return false;
//   }

//   void reset() {
//     _blinkCount = 0;
//     _inBlink = false;
//     _cooldown = false;
//     _blinkStart = null;
//   }
// }

// // ─────────────────────────────────────────────
// // CAMERA WIDGET
// // ─────────────────────────────────────────────

// class CameraWidget extends StatefulWidget {
//   const CameraWidget({super.key, required this.faceType});
//   final FaceType faceType;

//   @override
//   State<CameraWidget> createState() => _CameraWidgetState();
// }

// class _CameraWidgetState extends State<CameraWidget> with WidgetsBindingObserver, TickerProviderStateMixin {
//   CameraController? _controller;
//   List<CameraDescription> _cameras = [];
//   int _cameraIndex = 0;
//   bool _isStreaming = false;
//   bool _isAnalyzing = false;
//   bool _isCapturing = false;
//   int _frameCount = 0;
//   final FaceMatcher _faceMatcher = FaceMatcher(); // Add this
//   // static const double _faceMatchThreshold = 0.70; // Minimum similarity score to pass
//   // FIX: Track controller validity independently of CameraController.value.isInitialized.
//   // CameraController.value.isInitialized remains TRUE even after dispose() is called,
//   // so checking it alone is not sufficient to guard CameraPreview from a disposed controller.
//   bool _referenceFaceSet = false; // ADD THIS FLAG
//   bool _controllerReady = false; // Add dynamic threshold getter:
//   double get _faceMatchThreshold {
//     switch (_step.step) {
//       case LiveStep.lookStraight:
//         return 0.80; // Not used (no matching on step 1)
//       case LiveStep.blinkEyes:
//         return 0.78; // Similar angle to reference
//       case LiveStep.turnLeft:
//       case LiveStep.turnRight:
//         return 0.70; // Lower threshold for head turns (face looks different)
//       case LiveStep.smile:
//         return 0.75; // Medium threshold
//     }
//   }

//   late final FaceDetector _faceDetector;
//   late final ImageLabeler _imageLabeler;

//   int _labelFrame = 0;
//   List<ImageLabel> _lastLabels = [];

//   int _stepIndex = 0;
//   bool _stepCooldown = false;
//   bool _faceDetected = false;

//   // ── lookStraight hold timer ───────────────────────────────────────────────
//   // Step 1 used to pass on the very first valid frame (yaw < 12 is trivially
//   // true just by holding the phone).  Now the user must hold the pose
//   // continuously for [_straightRequiredMs] ms before it passes.
//   static const int _straightRequiredMs = 1500;
//   int _straightHeldMs = 0; // accumulated hold time in milliseconds
//   DateTime? _lastFrameTime; // wall-clock time of previous processed frame

//   final BlinkDetector _blinkDetector = BlinkDetector();
//   final FaceGuard _faceGuard = FaceGuard();
//   FaceGuardResult _guardResult = FaceGuardResult.ok;

//   String _statusText = 'Preparing camera…';
//   // Incremented on every _setFeedback call so AnimatedSwitcher always gets a
//   // unique key even when the message text itself hasn't changed.  Without this,
//   // two rapid setState calls with the same _statusText produce duplicate keys
//   // inside AnimatedSwitcher's internal Stack, causing a fatal assertion.
//   int _feedbackSeq = 0;
//   Color _ovalColor = Colors.white54;

//   late AnimationController _pulseCtrl;
//   late Animation<double> _pulse;
//   late AnimationController _checkCtrl;
//   late Animation<double> _check;

//   StepConfig get _step => kSteps[_stepIndex];

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);

//     _faceDetector = FaceDetector(
//       options: FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.fast,
//         enableLandmarks: true,
//         enableClassification: true,
//         enableTracking: false,
//       ),
//     );

//     _imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));

//     _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
//     _pulse = Tween<double>(
//       begin: 1.0,
//       end: 1.035,
//     ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

//     _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
//     _check = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);

//     _initCamera();
//   }

//   Future<void> _initCamera() async {
//     _cameras = await availableCameras();
//     if (_cameras.isEmpty) return;
//     final fi = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
//     _cameraIndex = fi != -1 ? fi : 0;
//     await _startCamera();
//   }

//   Future<void> _startCamera() async {
//     // FIX: Mark controller as NOT ready before any async work so that if a
//     // rebuild is triggered mid-initialization, CameraPreview is never shown
//     // against a partially-initialized or disposed controller.
//     if (mounted) setState(() => _controllerReady = false);

//     final old = _controller;
//     _controller = null;

//     // Stop the stream first, then dispose the old controller.
//     // Order matters: stopImageStream on an already-disposed controller throws.
//     if (old != null) {
//       try {
//         if (old.value.isStreamingImages) await old.stopImageStream();
//       } catch (_) {}
//       try {
//         await old.dispose();
//       } catch (_) {}
//     }
//     _isStreaming = false;
//     _faceMatcher.reset();
//     _referenceFaceSet = false; // ADD THIS
//     if (!mounted) return;

//     final controller = CameraController(
//       _cameras[_cameraIndex],
//       ResolutionPreset.medium,
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
//     );

//     _controller = controller;

//     try {
//       await controller.initialize();
//     } catch (e) {
//       log('Camera init error: $e');
//       return;
//     }

//     // FIX: Guard against widget disposal that happened while we were awaiting.
//     if (!mounted || _controller != controller) return;

//     await controller.setFlashMode(FlashMode.off);

//     // FIX: Set the ready flag BEFORE calling setState so the build method
//     // sees a consistent state and renders CameraPreview safely.
//     _controllerReady = true;
//     setState(() {
//       _statusText = kSteps[0].instruction;
//       _feedbackSeq++;
//     });

//     _startStream();
//   }

//   void _startStream() {
//     if (_isStreaming || _controller == null || !_controllerReady) return;
//     _isStreaming = true;
//     _controller!.startImageStream((CameraImage image) async {
//       _frameCount++;
//       if (_step.step != LiveStep.blinkEyes && _frameCount % 4 != 0) return;
//       if (_isAnalyzing || _isCapturing || _stepCooldown) return;
//       _isAnalyzing = true;
//       try {
//         await _processFrame(image);
//       } finally {
//         _isAnalyzing = false;
//       }
//     });
//   }

//   Future<void> _stopStream() async {
//     if (!_isStreaming) return;
//     _isStreaming = false;
//     try {
//       await _controller?.stopImageStream();
//     } catch (_) {}
//   }

//   Future<void> _processFrame(CameraImage image) async {
//     // FIX: Double-check readiness inside the stream callback, as the controller
//     // may have been disposed between frames.
//     if (!mounted || !_controllerReady) return;

//     try {
//       final cam = _cameras[_cameraIndex];
//       final isFront = cam.lensDirection == CameraLensDirection.front;
//       final input = _toInputImage(image, cam);
//       if (input == null) return;

//       final faces = await _faceDetector.processImage(input);

//       _labelFrame++;
//       // Run on frame 1 (immediate warmup for guard checks on step 1) and
//       // then every 10 frames.  Without frame-1 warmup, _lastLabels stays
//       // empty for the first ~10 frames, so glasses/sunglasses are invisible
//       // to FaceGuard until the very first labeler batch completes.
//       if (_labelFrame == 1 || _labelFrame % 10 == 0) {
//         _lastLabels = await _imageLabeler.processImage(input);
//         if (_lastLabels.isNotEmpty) {
//           log('🏷 ${_lastLabels.map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').join(', ')}');
//         }
//       }

//       if (!mounted) return;

//       if (faces.isEmpty) {
//         _setFeedback('No face detected — center your face', Colors.red, false);
//         setState(() => _guardResult = FaceGuardResult.ok);
//         return;
//       }
//       if (faces.length > 1) {
//         _setFeedback('Only one person allowed in frame', Colors.orange, false);
//         return;
//       }

//       final face = faces.first;
//       final nose = face.landmarks[FaceLandmarkType.noseBase];
//       final mouthL = face.landmarks[FaceLandmarkType.leftMouth];
//       final mouthR = face.landmarks[FaceLandmarkType.rightMouth];

//       final guard = _faceGuard.check(
//         face: face,
//         labels: _lastLabels,
//         hasNose: nose != null,
//         hasMouth: mouthL != null && mouthR != null,
//       );
//       setState(() => _guardResult = guard);

//       if (guard.blockStep) {
//         _setFeedback(guard.message, Colors.red, true);
//         return;
//       }

//       if (nose == null || mouthL == null || mouthR == null) {
//         _setFeedback('Keep your full face in the oval', Colors.orange, true);
//         return;
//       }

//       // ═══════════════════════════════════════════════════════════════
//       // FACE MATCHING - Ensure same person across all steps
//       // ═══════════════════════════════════════════════════════════════
//       // if (_stepIndex == 0) {
//       //   // On the first step, set reference face ONCE when user is stable
//       //   if (!_referenceFaceSet && _straightHeldMs >= 500) {
//       //     _faceMatcher.setReferenceFace(face);
//       //     _referenceFaceSet = true;
//       //     log('📸 Reference face captured and locked');
//       //   }
//       // } else {
//       //   // For all subsequent steps, verify it's the same person
//       //   if (_referenceFaceSet) {
//       //     final similarity = _faceMatcher.matchFace(face);
//       //     log('🔍 Face match score: ${similarity.toStringAsFixed(2)} (threshold: $_faceMatchThreshold)');

//       //     if (similarity < _faceMatchThreshold) {
//       //       _setFeedback('⚠️ Different person detected! The same person must complete all steps.', Colors.red, true);
//       //       return;
//       //     }
//       //   }
//       // }
//       // ═══════════════════════════════════════════════════════════════

//       setState(() => _faceDetected = true);

//       // ── Face-in-oval containment check ────────────────────────────────
//       // ML Kit bounding boxes are returned in different coordinate spaces
//       // depending on the platform:
//       //
//       // iOS (bgra8888):
//       //   The camera image arrives in LANDSCAPE orientation even when the
//       //   device is held in portrait.  ML Kit returns face coords in the
//       //   RAW (landscape) image space, so we must swap W/H before scaling.
//       //
//       // Android (nv21):
//       //   ML Kit's Android implementation internally handles rotation and
//       //   returns face coords already in the UPRIGHT (portrait) image space,
//       //   matching the image.width × image.height values directly.
//       //   DO NOT swap — it would flip the axes and break the mapping.
//       //
//       final screenSize = MediaQuery.of(context).size;
//       final imgW = image.width.toDouble();
//       final imgH = image.height.toDouble();

//       final bool isPortrait = screenSize.height > screenSize.width;
//       // Only swap on iOS where the raw frame is always landscape.
//       final bool shouldSwap = Platform.isIOS && isPortrait && imgW > imgH;
//       final double effectiveImgW = shouldSwap ? imgH : imgW;
//       final double effectiveImgH = shouldSwap ? imgW : imgH;

//       // CameraPreview uses BoxFit.cover — compute the actual rendered scale.
//       // Cover means the image is scaled so its SMALLER dimension fills the
//       // screen, then the larger dimension is cropped.  This means the scale
//       // factor is max(screenW/imgW, screenH/imgH), applied uniformly.
//       final double coverScale = [
//         screenSize.width / effectiveImgW,
//         screenSize.height / effectiveImgH,
//       ].reduce((a, b) => a > b ? a : b);

//       // Offset from cropping (the image is centred after cover scaling).
//       final double scaledImgW = effectiveImgW * coverScale;
//       final double scaledImgH = effectiveImgH * coverScale;
//       final double offsetX = (scaledImgW - screenSize.width) / 2;
//       final double offsetY = (scaledImgH - screenSize.height) / 2;

//       final faceBox = face.boundingBox;

//       // Scale face box from image coords → screen coords.
//       double faceLeft = faceBox.left * coverScale - offsetX;
//       double faceRight = faceBox.right * coverScale - offsetX;
//       double faceTop = faceBox.top * coverScale - offsetY;
//       double faceBottom = faceBox.bottom * coverScale - offsetY;

//       // Mirror X for front camera (preview is already mirrored on screen,
//       // but the bounding box is in the unmirrored image space).
//       if (isFront) {
//         final double mirroredLeft = screenSize.width - faceRight;
//         final double mirroredRight = screenSize.width - faceLeft;
//         faceLeft = mirroredLeft;
//         faceRight = mirroredRight;
//       }

//       final Rect faceScreenRect = Rect.fromLTRB(faceLeft, faceTop, faceRight, faceBottom);
//       final Rect oval = ovalRect(screenSize);

//       log(
//         '📐 face=$faceScreenRect oval=$oval isFront=$isFront swap=$shouldSwap coverScale=${coverScale.toStringAsFixed(2)}',
//       );

//       // IoF: intersection-over-face-area — what fraction of the face box
//       // falls inside the oval bounding rect.
//       final Rect intersection = faceScreenRect.intersect(oval);
//       final double faceArea = faceScreenRect.width * faceScreenRect.height;
//       final double iof = faceArea > 0
//           ? (intersection.width.clamp(0.0, double.infinity) * intersection.height.clamp(0.0, double.infinity)) /
//                 faceArea
//           : 0.0;

//       log('📐 IoF=${iof.toStringAsFixed(2)}');

//       if (iof < 0.75) {
//         // Face is not sufficiently inside the oval — give directional hint.
//         String hint = 'Move your face into the oval';
//         if (faceScreenRect.center.dy < oval.top + oval.height * 0.25) {
//           hint = '⬇️ Move your face down';
//         } else if (faceScreenRect.center.dy > oval.bottom - oval.height * 0.25) {
//           hint = '⬆️ Move your face up';
//         } else if (faceScreenRect.center.dx < oval.left + oval.width * 0.25) {
//           hint = '➡️ Move your face right';
//         } else if (faceScreenRect.center.dx > oval.right - oval.width * 0.25) {
//           hint = '⬅️ Move your face left';
//         } else if (faceScreenRect.height > oval.height * 1.1) {
//           hint = '🔙 Move further from camera';
//         } else if (faceScreenRect.height < oval.height * 0.55) {
//           hint = '🔜 Move closer to camera';
//         }
//         _setFeedback(hint, Colors.orange, true);
//         return;
//       }
//       // ── End containment check ──────────────────────────────────────────

//       double yaw = face.headEulerAngleY ?? 0;
//       if (isFront) yaw = -yaw;

//       _evaluate(face: face, yaw: yaw, smile: face.smilingProbability ?? 0.0);
//     } catch (e) {
//       log('Frame error: $e');
//     }
//   }

//   InputImage? _toInputImage(CameraImage image, CameraDescription cam) {
//     InputImageRotation? rotation;
//     if (Platform.isIOS) {
//       rotation = InputImageRotationValue.fromRawValue(cam.sensorOrientation);
//     } else {
//       var c = cam.sensorOrientation;
//       if (cam.lensDirection == CameraLensDirection.front) c = (360 - c) % 360;
//       rotation = InputImageRotationValue.fromRawValue(c);
//     }
//     if (rotation == null) return null;
//     final format = InputImageFormatValue.fromRawValue(image.format.raw);
//     if (format == null) return null;

//     if (image.planes.length == 1) {
//       return InputImage.fromBytes(
//         bytes: image.planes[0].bytes,
//         metadata: InputImageMetadata(
//           size: Size(image.width.toDouble(), image.height.toDouble()),
//           rotation: rotation,
//           format: format,
//           bytesPerRow: image.planes[0].bytesPerRow,
//         ),
//       );
//     }
//     final all = image.planes.fold<List<int>>([], (p, pl) => p..addAll(pl.bytes));
//     return InputImage.fromBytes(
//       bytes: Uint8List.fromList(all),
//       metadata: InputImageMetadata(
//         size: Size(image.width.toDouble(), image.height.toDouble()),
//         rotation: rotation,
//         format: format,
//         bytesPerRow: image.planes[0].bytesPerRow,
//       ),
//     );
//   }

//   void _evaluate({required Face face, required double yaw, required double smile}) {
//     bool passed = false;
//     switch (_step.step) {
//       case LiveStep.lookStraight:
//         final now = DateTime.now();
//         final frameGapMs = _lastFrameTime != null ? now.difference(_lastFrameTime!).inMilliseconds : 0;
//         _lastFrameTime = now;

//         if (yaw.abs() < 12) {
//           // Accumulate hold time, but cap each frame's contribution so a
//           // single very-slow frame (e.g. labeler warmup) doesn't skip ahead.
//           _straightHeldMs += frameGapMs.clamp(0, 200);
//         } else {
//           // User looked away — reset the counter.
//           _straightHeldMs = 0;
//           _setFeedback('Look straight at the camera', _step.color, true);
//           break;
//         }

//         if (_straightHeldMs >= _straightRequiredMs) {
//           passed = true;
//         } else {
//           // Show a live countdown so the user knows to keep still.
//           final remaining = ((_straightRequiredMs - _straightHeldMs) / 1000.0).ceil().clamp(
//             1,
//             (_straightRequiredMs / 1000).ceil(),
//           );
//           _setFeedback('Hold still… ${remaining}s', _step.color, true);
//         }
//         break;
//       case LiveStep.blinkEyes:
//         _blinkDetector.update(face.leftEyeOpenProbability, face.rightEyeOpenProbability);
//         passed = _blinkDetector.blinkCount >= 2;
//         if (!passed) {
//           final c = _blinkDetector.blinkCount;
//           _setFeedback(c == 0 ? 'Blink slowly and naturally' : 'Good! One more… $c / 2', _step.color, true);
//         }
//         break;
//       case LiveStep.turnLeft:
//         passed = yaw > 22;
//         if (!passed) _setFeedback('Turn head more to the LEFT ⬅️', _step.color, true);
//         break;
//       case LiveStep.turnRight:
//         passed = yaw < -22;
//         if (!passed) _setFeedback('Turn head more to the RIGHT ➡️', _step.color, true);
//         break;
//       case LiveStep.smile:
//         passed = smile > 0.75;
//         if (!passed) _setFeedback('Smile a little more 😊', _step.color, true);
//         break;
//     }
//     if (passed) _onPassed();
//   }

//   void _onPassed() {
//     _setFeedback('✓ Done!', Colors.green, true);
//     _checkCtrl.forward(from: 0);
//     _stepCooldown = true;
//     _blinkDetector.reset();
//     _straightHeldMs = 0;
//     _lastFrameTime = null;

//     Future.delayed(const Duration(milliseconds: 700), () {
//       if (!mounted) return;
//       if (_stepIndex < kSteps.length - 1) {
//         setState(() {
//           _stepIndex++;
//           _statusText = kSteps[_stepIndex].instruction;
//           _ovalColor = kSteps[_stepIndex].color;
//           _feedbackSeq++;
//         });
//         _stepCooldown = false;
//       } else {
//         _autoCapture();
//       }
//     });
//   }

//   Future<void> _autoCapture() async {
//     if (_isCapturing) return;
//     _isCapturing = true;
//     _setFeedback('✅ Capturing…', Colors.green, true);
//     await _stopStream();
//     try {
//       final file = await _controller!.takePicture();
//       final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
//       final renamed = XFile(file.path, name: 'face_$ts.jpeg', bytes: await file.readAsBytes());
//       if (!mounted) return;
//       setState(() {
//         _statusText = '✅ Verified!';
//         _ovalColor = Colors.green;
//         _feedbackSeq++;
//       });
//       await Future.delayed(const Duration(milliseconds: 900));
//       if (mounted) Navigator.pop(context, renamed);
//     } catch (e) {
//       log('Capture error: $e');
//       _isCapturing = false;
//       _startStream();
//       _setFeedback('Capture failed. Try again.', Colors.red, true);
//     }
//   }

//   void _setFeedback(String text, Color color, bool detected) {
//     if (!mounted) return;
//     setState(() {
//       _statusText = text;
//       _ovalColor = color;
//       _faceDetected = detected;
//       _feedbackSeq++; // always unique → AnimatedSwitcher key is never duplicated
//     });
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.inactive) {
//       // FIX: Mark not ready immediately so any pending rebuild triggered by
//       // the lifecycle change never passes a disposed controller to CameraPreview.
//       if (mounted) setState(() => _controllerReady = false);
//       _stopStream();
//       _controller?.dispose();
//       _controller = null;
//     } else if (state == AppLifecycleState.resumed) {
//       _startCamera();
//     }
//   }

//   @override
//   void dispose() {
//     _controllerReady = false;
//     WidgetsBinding.instance.removeObserver(this);
//     _pulseCtrl.dispose();
//     _checkCtrl.dispose();
//     _faceDetector.close();
//     _imageLabeler.close();
//     _faceMatcher.reset();
//     _referenceFaceSet = false; // ADD THIS
//     _stopStream();
//     _controller?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     // FIX: Use _controllerReady instead of (or in addition to) isInitialized.
//     // isInitialized alone is unreliable as a guard because CameraController
//     // keeps that flag true after dispose() — _controllerReady is set to false
//     // synchronously at the start of dispose() and _startCamera(), ensuring
//     // CameraPreview is never given a stale or disposed controller.
//     final ready = _controller != null && _controllerReady;
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: ready ? _buildBody() : const Center(child: CircularProgressIndicator()),
//     );
//   }

//   Widget _buildBody() {
//     final size = MediaQuery.of(context).size;
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         if (_stepIndex > 0 && _referenceFaceSet)
//           Positioned(
//             top: 130,
//             left: 16,
//             right: 16,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//               decoration: BoxDecoration(color: Colors.blue.withOpacity(0.8), borderRadius: BorderRadius.circular(12)),
//               child: Text(
//                 '🔍 Debug: Match Score - Check logs',
//                 style: const TextStyle(color: Colors.white, fontSize: 12),
//                 textAlign: TextAlign.center,
//               ),
//             ),
//           ),
//         CameraPreview(_controller!),

//         AnimatedBuilder(
//           animation: _pulse,
//           builder: (_, __) => CustomPaint(
//             painter: _OvalPainter(color: _guardResult.blockStep ? Colors.red : _ovalColor, scale: _pulse.value),
//             child: const SizedBox.expand(),
//           ),
//         ),

//         // "Align face here" label pinned just below the oval centre so the
//         // user knows where chin/forehead should land before a face is found.
//         if (!_faceDetected)
//           Positioned.fill(
//             child: LayoutBuilder(
//               builder: (ctx, constraints) {
//                 final size = Size(constraints.maxWidth, constraints.maxHeight);
//                 final oval = ovalRect(size);
//                 return Stack(
//                   children: [
//                     Positioned(
//                       top: oval.bottom + 8,
//                       left: 0,
//                       right: 0,
//                       child: Center(
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
//                           decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
//                           child: const Text(
//                             'Align your full face inside the oval',
//                             style: TextStyle(color: Colors.white70, fontSize: 12),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 );
//               },
//             ),
//           ),

//         SafeArea(
//           child: Align(
//             alignment: Alignment.topLeft,
//             child: IconButton(
//               icon: const Icon(Icons.close, color: Colors.white, size: 28),
//               onPressed: () => Navigator.pop(context),
//             ),
//           ),
//         ),

//         SafeArea(
//           child: Align(
//             alignment: Alignment.topCenter,
//             child: Padding(
//               padding: const EdgeInsets.only(top: 14, left: 64, right: 20),
//               child: Row(
//                 children: List.generate(
//                   kSteps.length,
//                   (i) => Expanded(
//                     child: AnimatedContainer(
//                       duration: const Duration(milliseconds: 300),
//                       height: 4,
//                       margin: const EdgeInsets.symmetric(horizontal: 2),
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(2),
//                         color: i < _stepIndex
//                             ? Colors.green
//                             : i == _stepIndex
//                             ? _step.color
//                             : Colors.white24,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),

//         if (_guardResult.blockStep)
//           Positioned(
//             top: 80,
//             left: 16,
//             right: 16,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//               decoration: BoxDecoration(color: Colors.red.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
//               child: Row(
//                 children: [
//                   Icon(
//                     _guardResult.warning == FaceWarning.sunglasses
//                         ? Icons.wb_sunny_outlined
//                         : _guardResult.warning == FaceWarning.eyeglasses
//                         ? Icons.visibility_outlined
//                         : Icons.warning_rounded,
//                     color: Colors.white,
//                     size: 20,
//                   ),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: Text(
//                       _guardResult.message,
//                       style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),

//         Positioned(
//           top: size.height * 0.17,
//           left: 0,
//           right: 0,
//           child: Center(
//             child: ScaleTransition(
//               scale: _check,
//               child: Container(
//                 padding: const EdgeInsets.all(10),
//                 decoration: BoxDecoration(
//                   color: _step.color.withOpacity(0.9),
//                   shape: BoxShape.circle,
//                   boxShadow: [BoxShadow(color: _step.color.withOpacity(0.4), blurRadius: 14)],
//                 ),
//                 child: Icon(_step.icon, color: Colors.white, size: 24),
//               ),
//             ),
//           ),
//         ),

//         Positioned(
//           bottom: 0,
//           left: 0,
//           right: 0,
//           child: Container(
//             padding: const EdgeInsets.fromLTRB(24, 18, 24, 44),
//             decoration: const BoxDecoration(
//               color: Color(0xE8000000),
//               borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   width: 36,
//                   height: 4,
//                   margin: const EdgeInsets.only(bottom: 14),
//                   decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
//                 ),

//                 Text(
//                   'Step ${_stepIndex + 1} of ${kSteps.length}',
//                   style: const TextStyle(color: Colors.white54, fontSize: 12),
//                 ),
//                 const SizedBox(height: 8),

//                 AnimatedSwitcher(
//                   duration: const Duration(milliseconds: 250),
//                   child: Text(
//                     _statusText,
//                     // KEY FIX: Use seq+text so the key is always unique even
//                     // when the same hint fires twice in a row.  Using only the
//                     // text means two consecutive identical messages get the same
//                     // key, leaving two children with duplicate keys in
//                     // AnimatedSwitcher's internal Stack → fatal assertion.
//                     key: ValueKey('$_feedbackSeq:$_statusText'),
//                     textAlign: TextAlign.center,
//                     style: TextStyle(
//                       color: _guardResult.blockStep || !_faceDetected ? Colors.redAccent : Colors.white,
//                       fontSize: 17,
//                       fontWeight: FontWeight.w600,
//                       height: 1.3,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 14),

//                 // ── lookStraight hold progress bar ─────────────────────────
//                 if (_step.step == LiveStep.lookStraight) ...[
//                   SizedBox(
//                     width: 200,
//                     child: Column(
//                       children: [
//                         ClipRRect(
//                           borderRadius: BorderRadius.circular(4),
//                           child: LinearProgressIndicator(
//                             value: (_straightHeldMs / _straightRequiredMs).clamp(0.0, 1.0),
//                             minHeight: 6,
//                             backgroundColor: Colors.white12,
//                             valueColor: AlwaysStoppedAnimation<Color>(_step.color),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 14),
//                 ],

//                 if (_step.step == LiveStep.blinkEyes) ...[
//                   Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: List.generate(2, (i) {
//                       final done = i < _blinkDetector.blinkCount;
//                       return AnimatedContainer(
//                         duration: const Duration(milliseconds: 300),
//                         margin: const EdgeInsets.symmetric(horizontal: 8),
//                         width: 44,
//                         height: 44,
//                         decoration: BoxDecoration(
//                           shape: BoxShape.circle,
//                           color: done ? Colors.green : Colors.white10,
//                           border: Border.all(color: done ? Colors.green : Colors.white38, width: 2),
//                         ),
//                         child: Icon(
//                           done ? Icons.check : Icons.remove_red_eye_outlined,
//                           color: done ? Colors.white : Colors.white38,
//                           size: 20,
//                         ),
//                       );
//                     }),
//                   ),
//                   const SizedBox(height: 14),
//                 ],

//                 AnimatedContainer(
//                   duration: const Duration(milliseconds: 300),
//                   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(20),
//                     border: Border.all(color: _faceDetected ? Colors.green : Colors.redAccent),
//                     color: (_faceDetected ? Colors.green : Colors.red).withOpacity(0.12),
//                   ),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Icon(
//                         _faceDetected ? Icons.check_circle_outline : Icons.warning_amber_rounded,
//                         color: _faceDetected ? Colors.green : Colors.orange,
//                         size: 14,
//                       ),
//                       const SizedBox(width: 6),
//                       Text(
//                         _faceDetected ? 'Face detected' : 'No face detected',
//                         style: TextStyle(color: _faceDetected ? Colors.green : Colors.orange, fontSize: 13),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

// // ─────────────────────────────────────────────
// // OVAL GEOMETRY — shared between painter & containment check
// // ─────────────────────────────────────────────
// //
// // centerYFactor : vertical center of oval as a fraction of screen height.
// //   0.42 was too high (caught hair/forehead). 0.46 centres the oval on the
// //   middle of a typical selfie face.
// //
// // widthFactor / heightFactor : oval dimensions as fractions of screen size.
// //   Made taller (0.52) so chin-to-forehead fits in the oval on most phones.
// //
// const double kOvalCenterYFactor = 0.46;
// const double kOvalWidthFactor = 0.72;
// const double kOvalHeightFactor = 0.52;

// /// Returns the oval Rect in screen/widget coordinates.
// Rect ovalRect(Size size, {double scale = 1.0}) => Rect.fromCenter(
//   center: Offset(size.width / 2, size.height * kOvalCenterYFactor),
//   width: size.width * kOvalWidthFactor * scale,
//   height: size.height * kOvalHeightFactor * scale,
// );

// // ─────────────────────────────────────────────
// // OVAL PAINTER
// // ─────────────────────────────────────────────

// class _OvalPainter extends CustomPainter {
//   final Color color;
//   final double scale;
//   _OvalPainter({required this.color, required this.scale});

//   @override
//   void paint(Canvas canvas, Size size) {
//     canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
//     canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black.withOpacity(0.55));
//     final oval = ovalRect(size, scale: scale);
//     canvas.drawOval(oval, Paint()..blendMode = BlendMode.clear);
//     canvas.restore();
//     canvas.drawOval(
//       oval,
//       Paint()
//         ..color = color
//         ..style = PaintingStyle.stroke
//         ..strokeWidth = 3.5,
//     );
//     // Guide tick marks so the user can see where to align chin/forehead/ears.
//     final tickPaint = Paint()
//       ..color = color.withOpacity(0.7)
//       ..strokeWidth = 2.5
//       ..strokeCap = StrokeCap.round;
//     const tickLen = 12.0;
//     canvas.drawLine(Offset(oval.center.dx, oval.top), Offset(oval.center.dx, oval.top + tickLen), tickPaint);
//     canvas.drawLine(Offset(oval.center.dx, oval.bottom), Offset(oval.center.dx, oval.bottom - tickLen), tickPaint);
//     canvas.drawLine(Offset(oval.left, oval.center.dy), Offset(oval.left + tickLen, oval.center.dy), tickPaint);
//     canvas.drawLine(Offset(oval.right, oval.center.dy), Offset(oval.right - tickLen, oval.center.dy), tickPaint);
//   }

//   @override
//   bool shouldRepaint(_OvalPainter old) => old.color != color || old.scale != scale;
// }
