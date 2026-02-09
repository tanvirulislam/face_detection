import 'dart:developer';

import 'package:face_detection/camera.widget.dart';
import 'package:face_detection/enum.dart';
import 'package:face_detection/face_matching/helper.method.dart';
import 'package:face_detection/face_matching/provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tensorflow_face_verification/tensorflow_face_verification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initialize();
  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Detection Validation',
      theme: ThemeData(primarySwatch: Colors.blue),
      // home: Scaffold(body: CameraWidget()),
      home: Home(),
    );
  }
}

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final frontImg = ref.watch(provider1);
    final leftImg = ref.watch(provider2);
    final rightImg = ref.watch(provider3);
    final message = 'Front: ${frontImg?.name}, Left: ${leftImg?.name}, Right: ${rightImg?.name}';
    log('message: $message');
    return Scaffold(
      appBar: AppBar(title: const Text('Face Detection Validation')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraWidget(faceType: FaceType.front)),
                );
              },
              child: const Text('Front Face'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraWidget(faceType: FaceType.left)));
              },
              child: const Text('Left Face'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraWidget(faceType: FaceType.right)),
                );
              },
              child: const Text('Right Face'),
            ),
            ElevatedButton(
              onPressed: () async {
                final score = await compareFaces(frontImg?.path ?? '', leftImg?.path ?? '');
                log('score: $score');
                bool isSame = await isSamePerson(frontImg?.path ?? '', leftImg?.path ?? '');
                log('isSame: $isSame');
              },
              child: const Text('Compare Faces'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> initialize() async {
  try {
    await FaceVerification.init(modelPath: 'assets/model/facenet.tflite');

    print('✅ Face verification model loaded');
  } catch (e) {
    print('❌ Failed to load model: $e');
    rethrow;
  }
}
