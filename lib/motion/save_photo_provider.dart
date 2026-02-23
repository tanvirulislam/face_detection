import 'package:camera/camera.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'save_photo_provider.g.dart';

@Riverpod(keepAlive: true)
class ClickedPhoto extends _$ClickedPhoto {
  @override
  XFile? build(String arg) => null;
  void setImage(XFile? value) => state = value;
}
