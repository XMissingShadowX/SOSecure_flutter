// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contacts_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$contactsHash() => r'31c27fc5f93f696f928efc0ec94d59d7303030bc';

/// See also [Contacts].
@ProviderFor(Contacts)
final contactsProvider =
    AutoDisposeAsyncNotifierProvider<Contacts, List<EmergencyContact>>.internal(
      Contacts.new,
      name: r'contactsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$contactsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$Contacts = AutoDisposeAsyncNotifier<List<EmergencyContact>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
