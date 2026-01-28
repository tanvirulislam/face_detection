export 'js_bridge_stub.dart' if (dart.library.html) 'js_bridge_web.dart';
import 'package:js/js.dart';

@JS('detectFaceFromImage')
external Object detectFaceFromImage(String base64Image);
