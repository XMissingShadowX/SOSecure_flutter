// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_history_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$alertHistoryDaysHash() => r'f4f787d4802b84eaa396b3114fd2ed06017e1cab';

/// See also [AlertHistoryDays].
@ProviderFor(AlertHistoryDays)
final alertHistoryDaysProvider =
    AutoDisposeNotifierProvider<AlertHistoryDays, int>.internal(
      AlertHistoryDays.new,
      name: r'alertHistoryDaysProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$alertHistoryDaysHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AlertHistoryDays = AutoDisposeNotifier<int>;
String _$alertHistoryHash() => r'88c7e1d9b71955276636f2fe26a6c798376b2385';

/// See also [AlertHistory].
@ProviderFor(AlertHistory)
final alertHistoryProvider =
    AutoDisposeAsyncNotifierProvider<AlertHistory, List<SosAlert>>.internal(
      AlertHistory.new,
      name: r'alertHistoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$alertHistoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AlertHistory = AutoDisposeAsyncNotifier<List<SosAlert>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
