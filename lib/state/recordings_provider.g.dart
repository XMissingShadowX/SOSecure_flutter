// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recordings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$recordingsHash() => r'53ecdeadda5838c5e6d6fa9debb1b7b9bc04a64c';

/// See also [Recordings].
@ProviderFor(Recordings)
final recordingsProvider =
    AutoDisposeAsyncNotifierProvider<
      Recordings,
      List<StoredRecording>
    >.internal(
      Recordings.new,
      name: r'recordingsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$recordingsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$Recordings = AutoDisposeAsyncNotifier<List<StoredRecording>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
