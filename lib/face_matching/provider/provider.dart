import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final provider1 = NotifierProvider.autoDispose<FileOneNotifier, XFile?>(FileOneNotifier.new);

class FileOneNotifier extends Notifier<XFile?> {
  @override
  XFile? build() => null;
  void add(XFile? value) => state = value;
}

final provider2 = NotifierProvider.autoDispose<FileOneNotifier2, XFile?>(FileOneNotifier2.new);

class FileOneNotifier2 extends Notifier<XFile?> {
  @override
  XFile? build() => null;
  void add(XFile? value) => state = value;
}

final provider3 = NotifierProvider.autoDispose<FileOneNotifier3, XFile?>(FileOneNotifier3.new);

class FileOneNotifier3 extends Notifier<XFile?> {
  @override
  XFile? build() => null;
  void add(XFile? value) => state = value;
}
