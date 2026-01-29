export 'js_bridge_stub.dart' if (dart.library.html) 'web/js_bridge_web.dart';

import 'package:js/js.dart';

@JS('detectFaceFromImage')
external Object detectFaceFromImage(String base64Image);
