import 'package:shared_preferences/shared_preferences.dart';

enum UserSex {
  male('男'),
  female('女'),
  other('其他');

  const UserSex(this.label);

  final String label;
}

class UserProfile {
  const UserProfile({
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.sex,
  });

  final double heightCm;
  final double weightKg;
  final int age;
  final UserSex sex;

  static const UserProfile defaults = UserProfile(
    heightCm: 170,
    weightKg: 70,
    age: 30,
    sex: UserSex.other,
  );

  static Future<UserProfile> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? sexValue = prefs.getString(_sexKey);

    return UserProfile(
      heightCm: prefs.getDouble(_heightKey) ?? defaults.heightCm,
      weightKg: prefs.getDouble(_weightKey) ?? defaults.weightKg,
      age: prefs.getInt(_ageKey) ?? defaults.age,
      sex: UserSex.values.firstWhere(
        (UserSex sex) => sex.name == sexValue,
        orElse: () => defaults.sex,
      ),
    );
  }

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_heightKey, heightCm);
    await prefs.setDouble(_weightKey, weightKg);
    await prefs.setInt(_ageKey, age);
    await prefs.setString(_sexKey, sex.name);
  }

  String get summary =>
      '${heightCm.toStringAsFixed(0)} cm / ${weightKg.toStringAsFixed(0)} kg / $age 歲 / ${sex.label}';

  UserProfile copyWith({
    double? heightCm,
    double? weightKg,
    int? age,
    UserSex? sex,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      age: age ?? this.age,
      sex: sex ?? this.sex,
    );
  }

  static const String _heightKey = 'user_profile_height_cm';
  static const String _weightKey = 'user_profile_weight_kg';
  static const String _ageKey = 'user_profile_age';
  static const String _sexKey = 'user_profile_sex';
}
