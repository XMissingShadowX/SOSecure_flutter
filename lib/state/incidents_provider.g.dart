// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'incidents_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$incidentsHash() => r'd8db73652c9d2997b18e455978fdf5435b98ebb6';

/// See also [Incidents].
@ProviderFor(Incidents)
final incidentsProvider =
    AsyncNotifierProvider<Incidents, List<Incident>>.internal(
      Incidents.new,
      name: r'incidentsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$incidentsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$Incidents = AsyncNotifier<List<Incident>>;
String _$mapPermissionsHash() => r'6fada85a683310d156cb7f38a0512e22fa296386';

/// See also [MapPermissions].
@ProviderFor(MapPermissions)
final mapPermissionsProvider =
    AutoDisposeAsyncNotifierProvider<
      MapPermissions,
      ({String? userId, bool isAdmin})
    >.internal(
      MapPermissions.new,
      name: r'mapPermissionsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$mapPermissionsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$MapPermissions =
    AutoDisposeAsyncNotifier<({String? userId, bool isAdmin})>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
