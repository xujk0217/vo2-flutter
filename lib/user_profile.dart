import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo2_flutter/receiver/device_protocol.dart';

enum UserSex {
  male('男'),
  female('女'),
  other('其他');

  const UserSex(this.label);

  final String label;
}

class UserProfile {
  const UserProfile({
    this.id = _defaultProfileId,
    this.displayName = _defaultDisplayName,
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.sex,
    this.vo2Max,
  });

  final String id;
  final String displayName;
  final double heightCm;
  final double weightKg;
  final int age;
  final UserSex sex;
  final int? vo2Max;

  static const UserProfile defaults = UserProfile(
    id: _defaultProfileId,
    displayName: _defaultDisplayName,
    heightCm: 170,
    weightKg: 70,
    age: 30,
    sex: UserSex.other,
  );

  static Future<List<UserProfile>> loadProfiles() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<UserProfile> loadedProfiles = _loadProfilesFromJsonString(
      prefs.getString(_profilesKey),
    );

    if (loadedProfiles.isNotEmpty) {
      return loadedProfiles;
    }

    final UserProfile? legacyProfile = _loadLegacyProfile(prefs);
    if (legacyProfile == null) {
      return const <UserProfile>[];
    }

    final List<UserProfile> migratedProfiles = <UserProfile>[legacyProfile];
    await saveProfiles(migratedProfiles);
    await saveSelectedProfileId(legacyProfile.id);
    return migratedProfiles;
  }

  static Future<void> saveProfiles(List<UserProfile> profiles) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (profiles.isEmpty) {
      await prefs.remove(_profilesKey);
      return;
    }

    final List<Map<String, dynamic>> encodedProfiles = profiles
        .where((UserProfile profile) => profile.id.isNotEmpty)
        .map((UserProfile profile) => profile.toJson())
        .toList();
    await prefs.setString(_profilesKey, jsonEncode(encodedProfiles));
  }

  static Future<String?> loadSelectedProfileId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedProfileIdKey);
  }

  static Future<void> saveSelectedProfileId(String? profileId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (profileId == null) {
      await prefs.remove(_selectedProfileIdKey);
    } else {
      await prefs.setString(_selectedProfileIdKey, profileId);
    }
  }

  static Future<UserProfile> loadSelectedProfile() async {
    final List<UserProfile> profiles = await loadProfiles();
    if (profiles.isEmpty) {
      return defaults;
    }

    final String? selectedProfileId = await loadSelectedProfileId();
    if (selectedProfileId == null) {
      return profiles.first;
    }

    for (final UserProfile profile in profiles) {
      if (profile.id == selectedProfileId) {
        return profile;
      }
    }

    return profiles.first;
  }

  static UserProfile fromJson(Map<String, dynamic> json) {
    final String id = json['id'] is String
        ? json['id'] as String
        : _defaultProfileId;
    return UserProfile(
      id: id,
      displayName: json['displayName'] is String
          ? json['displayName'] as String
          : _defaultDisplayName,
      heightCm: _asDouble(json['heightCm'], defaults.heightCm),
      weightKg: _asDouble(json['weightKg'], defaults.weightKg),
      age: _asInt(json['age'], defaults.age),
      sex: _parseSex(json['sex']),
      vo2Max: _asIntNullable(json['vo2Max']),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'age': age,
      'sex': sex.name,
    };

    final int? vo2 = vo2Max;
    if (vo2 != null) {
      data['vo2Max'] = vo2;
    }
    return data;
  }

  static Future<UserProfile> load() async {
    return loadSelectedProfile();
  }

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<UserProfile> existingProfiles = await loadProfiles();

    final List<UserProfile> updatedProfiles = <UserProfile>[];
    bool replaced = false;
    for (final UserProfile profile in existingProfiles) {
      if (profile.id == id) {
        updatedProfiles.add(this);
        replaced = true;
      } else {
        updatedProfiles.add(profile);
      }
    }
    if (!replaced) {
      updatedProfiles.add(this);
    }

    await saveProfiles(updatedProfiles);
    await saveSelectedProfileId(id);

    // Preserve compatibility with previous single-profile persistence behavior.
    await prefs.setDouble(_heightKey, heightCm);
    await prefs.setDouble(_weightKey, weightKg);
    await prefs.setInt(_ageKey, age);
    await prefs.setString(_sexKey, sex.name);
    await prefs.setString(_heightDisplayNameKey, displayName);
    if (vo2Max == null) {
      await prefs.remove(_vo2MaxKey);
    } else {
      await prefs.setInt(_vo2MaxKey, vo2Max!);
    }
  }

  String get summary =>
      '${_displayNameSummaryPart()}${heightCm.toStringAsFixed(0)} cm / ${weightKg.toStringAsFixed(0)} kg / $age 歲 / ${sex.label}${_vo2MaxSummaryPart()}';

  DeviceProfilePayload get deviceProfilePayload {
    return DeviceProfilePayload(
      heightCm: heightCm.round().clamp(80, 250),
      weightKg: weightKg.round().clamp(20, 250),
      age: age.clamp(5, 120),
      sex: _sexToPayloadSex(),
      vo2Max: vo2Max,
    );
  }

  UserProfile copyWith({
    String? id,
    String? displayName,
    double? heightCm,
    double? weightKg,
    int? age,
    UserSex? sex,
    int? vo2Max,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      age: age ?? this.age,
      sex: sex ?? this.sex,
      vo2Max: vo2Max ?? this.vo2Max,
    );
  }

  static const String _profilesKey = 'user_profile_profiles_json';
  static const String _selectedProfileIdKey =
      'user_profile_selected_profile_id';

  static const String _heightKey = 'user_profile_height_cm';
  static const String _weightKey = 'user_profile_weight_kg';
  static const String _ageKey = 'user_profile_age';
  static const String _sexKey = 'user_profile_sex';
  static const String _vo2MaxKey = 'user_profile_vo2_max';
  static const String _heightDisplayNameKey = 'user_profile_display_name';

  static const String _defaultProfileId = 'default-user-profile';
  static const String _defaultDisplayName = '預設使用者';

  String _displayNameSummaryPart() {
    if (id == _defaultProfileId && displayName == _defaultDisplayName) {
      return '';
    }
    if (displayName.trim().isEmpty) {
      return '';
    }
    return '$displayName / ';
  }

  String _vo2MaxSummaryPart() {
    if (vo2Max == null) {
      return '';
    }
    return ' / VO2max $vo2Max';
  }

  int _sexToPayloadSex() {
    switch (sex) {
      case UserSex.male:
        return 0;
      case UserSex.female:
        return 1;
      case UserSex.other:
        return 2;
    }
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static int? _asIntNullable(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static UserSex _parseSex(Object? value) {
    if (value is String) {
      return UserSex.values.firstWhere(
        (UserSex sex) => sex.name == value,
        orElse: () => defaults.sex,
      );
    }
    if (value is int) {
      final int index = value.clamp(0, UserSex.values.length - 1);
      return UserSex.values[index];
    }

    return defaults.sex;
  }

  static List<UserProfile> _loadProfilesFromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return const <UserProfile>[];
    }

    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        return const <UserProfile>[];
      }

      final List<UserProfile> loadedProfiles = <UserProfile>[];
      for (final Object? item in decoded) {
        if (item is Map<String, dynamic>) {
          loadedProfiles.add(UserProfile.fromJson(item));
        } else if (item is Map<dynamic, dynamic>) {
          loadedProfiles.add(
            UserProfile.fromJson(
              item.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
      return loadedProfiles;
    } catch (_) {
      return const <UserProfile>[];
    }
  }

  static UserProfile? _loadLegacyProfile(SharedPreferences prefs) {
    if (!prefs.containsKey(_heightKey) &&
        !prefs.containsKey(_weightKey) &&
        !prefs.containsKey(_ageKey) &&
        !prefs.containsKey(_sexKey) &&
        !prefs.containsKey(_heightDisplayNameKey) &&
        !prefs.containsKey(_vo2MaxKey)) {
      return null;
    }

    return UserProfile(
      id: _defaultProfileId,
      displayName:
          prefs.getString(_heightDisplayNameKey) ?? _defaultDisplayName,
      heightCm: prefs.getDouble(_heightKey) ?? defaults.heightCm,
      weightKg: prefs.getDouble(_weightKey) ?? defaults.weightKg,
      age: prefs.getInt(_ageKey) ?? defaults.age,
      sex: _parseSex(prefs.getString(_sexKey)),
      vo2Max: prefs.getInt(_vo2MaxKey),
    );
  }
}
