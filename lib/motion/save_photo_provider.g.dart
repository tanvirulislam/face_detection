// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_photo_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ClickedPhoto)
final clickedPhotoProvider = ClickedPhotoFamily._();

final class ClickedPhotoProvider
    extends $NotifierProvider<ClickedPhoto, XFile?> {
  ClickedPhotoProvider._({
    required ClickedPhotoFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clickedPhotoProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clickedPhotoHash();

  @override
  String toString() {
    return r'clickedPhotoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ClickedPhoto create() => ClickedPhoto();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XFile? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XFile?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClickedPhotoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clickedPhotoHash() => r'5ddb8999a45bcaf24782cb113d59c1433720fcf4';

final class ClickedPhotoFamily extends $Family
    with $ClassFamilyOverride<ClickedPhoto, XFile?, XFile?, XFile?, String> {
  ClickedPhotoFamily._()
    : super(
        retry: null,
        name: r'clickedPhotoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  ClickedPhotoProvider call(String arg) =>
      ClickedPhotoProvider._(argument: arg, from: this);

  @override
  String toString() => r'clickedPhotoProvider';
}

abstract class _$ClickedPhoto extends $Notifier<XFile?> {
  late final _$args = ref.$arg as String;
  String get arg => _$args;

  XFile? build(String arg);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<XFile?, XFile?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<XFile?, XFile?>,
              XFile?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
