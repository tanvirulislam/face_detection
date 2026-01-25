import 'package:face_detection/camera.widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: Scaffold(body: CameraWidget()),
    );
  }
}

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   final cameras = await availableCameras();
//   runApp(MyApp(cameras: cameras));
// }

// class MyApp extends StatelessWidget {
//   final List<CameraDescription> cameras;

//   const MyApp({super.key, required this.cameras});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Face Detection Validation',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: Scaffold(
//         appBar: AppBar(title: const Text('Face Detection Validation')),
//         body: Column(children: []),
//       ),
//     );
//   }
// }
