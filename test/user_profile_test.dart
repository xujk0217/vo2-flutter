import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/user_profile.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loadProfiles loads and persists JSON list profiles', () async {
    const List<UserProfile> savedProfiles = <UserProfile>[
      UserProfile(
        id: 'p1',
        displayName: 'Alice',
        heightCm: 175,
        weightKg: 60,
        age: 28,
        sex: UserSex.female,
        vo2Max: 42,
      ),
      UserProfile(
        id: 'p2',
        displayName: 'Bob',
        heightCm: 168,
        weightKg: 72,
        age: 33,
        sex: UserSex.male,
      ),
    ];

    await UserProfile.saveProfiles(savedProfiles);

    final List<UserProfile> loadedProfiles = await UserProfile.loadProfiles();
    expect(loadedProfiles, hasLength(2));
    expect(loadedProfiles[0].id, 'p1');
    expect(loadedProfiles[0].displayName, 'Alice');
    expect(loadedProfiles[0].vo2Max, 42);
    expect(loadedProfiles[1].id, 'p2');
    expect(loadedProfiles[1].displayName, 'Bob');
    expect(loadedProfiles[1].vo2Max, isNull);
  });

  test('selected profile id is persisted and restored', () async {
    await UserProfile.saveSelectedProfileId('p2');
    expect(await UserProfile.loadSelectedProfileId(), 'p2');

    await UserProfile.saveSelectedProfileId(null);
    expect(await UserProfile.loadSelectedProfileId(), isNull);
  });

  test(
    'loadSelectedProfile falls back to first profile when selection missing',
    () async {
      const List<UserProfile> savedProfiles = <UserProfile>[
        UserProfile(
          id: 'p1',
          displayName: 'Alice',
          heightCm: 175,
          weightKg: 60,
          age: 28,
          sex: UserSex.female,
        ),
        UserProfile(
          id: 'p2',
          displayName: 'Bob',
          heightCm: 168,
          weightKg: 72,
          age: 33,
          sex: UserSex.male,
        ),
      ];
      await UserProfile.saveProfiles(savedProfiles);

      final UserProfile selected = await UserProfile.loadSelectedProfile();
      expect(selected.id, 'p1');

      await UserProfile.saveSelectedProfileId('p2');
      final UserProfile selectedById = await UserProfile.loadSelectedProfile();
      expect(selectedById.id, 'p2');
    },
  );

  test(
    'loadProfiles migrates legacy single-profile keys and loadSelectedProfile returns it',
    () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_profile_height_cm', 181);
      await prefs.setDouble('user_profile_weight_kg', 78);
      await prefs.setInt('user_profile_age', 31);
      await prefs.setString('user_profile_sex', 'male');
      await prefs.setString('user_profile_display_name', 'Legacy Tester');
      await prefs.setInt('user_profile_vo2_max', 39);

      final List<UserProfile> migratedProfiles =
          await UserProfile.loadProfiles();
      expect(migratedProfiles, hasLength(1));
      final UserProfile migrated = migratedProfiles.first;
      expect(migrated.id, UserProfile.defaults.id);
      expect(migrated.displayName, 'Legacy Tester');
      expect(migrated.heightCm, 181);
      expect(migrated.weightKg, 78);
      expect(migrated.age, 31);
      expect(migrated.sex, UserSex.male);
      expect(migrated.vo2Max, 39);

      final UserProfile selected = await UserProfile.loadSelectedProfile();
      expect(selected.id, migrated.id);
      expect(selected.displayName, migrated.displayName);
      expect(selected.heightCm, migrated.heightCm);
      expect(selected.weightKg, migrated.weightKg);
      expect(selected.age, migrated.age);
      expect(selected.sex, migrated.sex);
      expect(selected.vo2Max, migrated.vo2Max);
      expect(
        await UserProfile.loadSelectedProfileId(),
        UserProfile.defaults.id,
      );
    },
  );

  test(
    'summary and payload helper include display name and optional VO2 max',
    () {
      const UserProfile withDisplayName = UserProfile(
        id: 'test-id',
        displayName: 'Carol',
        heightCm: 170,
        weightKg: 70,
        age: 30,
        sex: UserSex.other,
        vo2Max: 45,
      );
      expect(withDisplayName.summary, contains('Carol'));
      expect(withDisplayName.summary, contains('VO2max 45'));

      final profilePayload = withDisplayName.deviceProfilePayload;
      expect(profilePayload.vo2Max, 45);
      expect(profilePayload.sex, 2);

      const UserProfile minimalDefaultStyle = UserProfile(
        heightCm: 170,
        weightKg: 70,
        age: 30,
        sex: UserSex.other,
      );
      expect(minimalDefaultStyle.summary, UserProfile.defaults.summary);
    },
  );
}
