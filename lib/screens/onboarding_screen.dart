import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/user_profile.dart';

typedef UserProfileSelected = void Function(UserProfile profile);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onProfileSelected});

  static const String routeName = '/onboarding';

  final UserProfileSelected? onProfileSelected;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _vo2MaxController = TextEditingController();

  List<UserProfile> _profiles = const <UserProfile>[];
  String? _selectedProfileId;
  UserSex _sex = UserSex.other;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showAddForm = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    _vo2MaxController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final List<UserProfile> profiles = await UserProfile.loadProfiles();
    final String? selectedProfileId = await UserProfile.loadSelectedProfileId();
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = profiles;
      _selectedProfileId =
          profiles.any((UserProfile profile) => profile.id == selectedProfileId)
          ? selectedProfileId
          : profiles.isNotEmpty
          ? profiles.first.id
          : null;
      _showAddForm = profiles.isEmpty;
      _isLoading = false;
    });
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '請填寫此欄位';
    }
    return null;
  }

  String? _numberInRange(String? value, double min, double max) {
    final String? requiredMessage = _requiredText(value);
    if (requiredMessage != null) {
      return requiredMessage;
    }
    final double? parsed = double.tryParse(value!.trim());
    if (parsed == null || parsed < min || parsed > max) {
      return '請輸入 $min - $max 之間的數值';
    }
    return null;
  }

  String? _optionalVo2Max(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final int? parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 5 || parsed > 100) {
      return 'VO2max 需介於 5 - 100';
    }
    return null;
  }

  Future<void> _saveNewProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final UserProfile profile = UserProfile(
      id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
      displayName: _displayNameController.text.trim(),
      heightCm: double.parse(_heightController.text.trim()).clamp(80, 250),
      weightKg: double.parse(_weightController.text.trim()).clamp(20, 250),
      age: int.parse(_ageController.text.trim()).clamp(5, 120),
      sex: _sex,
      vo2Max: _vo2MaxController.text.trim().isEmpty
          ? null
          : int.parse(_vo2MaxController.text.trim()),
    );
    final List<UserProfile> updatedProfiles = <UserProfile>[
      ..._profiles,
      profile,
    ];
    await UserProfile.saveProfiles(updatedProfiles);
    await UserProfile.saveSelectedProfileId(profile.id);

    if (!mounted) {
      return;
    }
    widget.onProfileSelected?.call(profile);
    setState(() {
      _profiles = updatedProfiles;
      _selectedProfileId = profile.id;
      _showAddForm = false;
      _isSaving = false;
    });
    Navigator.of(context).pushNamed(ConnectionScreen.routeName);
  }

  Future<void> _confirmSelectedProfile() async {
    final UserProfile? profile = _selectedProfile();
    if (profile == null) {
      setState(() {
        _showAddForm = true;
      });
      return;
    }

    await UserProfile.saveSelectedProfileId(profile.id);
    if (!mounted) {
      return;
    }
    widget.onProfileSelected?.call(profile);
    Navigator.of(context).pushNamed(ConnectionScreen.routeName);
  }

  UserProfile? _selectedProfile() {
    for (final UserProfile profile in _profiles) {
      if (profile.id == _selectedProfileId) {
        return profile;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VO2 Motion Monitor')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: <Widget>[
                  Text(
                    '先選擇使用者',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '個人資料會先送到 BLE 裝置，接著進入連線與校正流程。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_profiles.isNotEmpty) ...<Widget>[
                    _ProfileSelectionCard(
                      profiles: _profiles,
                      selectedProfileId: _selectedProfileId,
                      onProfileSelected: (String profileId) {
                        setState(() {
                          _selectedProfileId = profileId;
                        });
                      },
                      onConfirmPressed: _confirmSelectedProfile,
                      onAddPressed: () {
                        setState(() {
                          _showAddForm = true;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_showAddForm)
                    _AddProfileCard(
                      formKey: _formKey,
                      displayNameController: _displayNameController,
                      heightController: _heightController,
                      weightController: _weightController,
                      ageController: _ageController,
                      vo2MaxController: _vo2MaxController,
                      sex: _sex,
                      isSaving: _isSaving,
                      onSexChanged: (UserSex sex) {
                        setState(() {
                          _sex = sex;
                        });
                      },
                      onSavePressed: _saveNewProfile,
                      requiredTextValidator: _requiredText,
                      numberValidator: _numberInRange,
                      optionalVo2MaxValidator: _optionalVo2Max,
                    ),
                ],
              ),
      ),
    );
  }
}

class _ProfileSelectionCard extends StatelessWidget {
  const _ProfileSelectionCard({
    required this.profiles,
    required this.selectedProfileId,
    required this.onProfileSelected,
    required this.onConfirmPressed,
    required this.onAddPressed,
  });

  final List<UserProfile> profiles;
  final String? selectedProfileId;
  final ValueChanged<String> onProfileSelected;
  final VoidCallback onConfirmPressed;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '選擇使用者',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...profiles.map((UserProfile profile) {
            final bool selected = profile.id == selectedProfileId;
            return Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(profile.displayName),
                subtitle: Text(profile.summary),
                onTap: () => onProfileSelected(profile.id),
              ),
            );
          }),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onConfirmPressed,
                icon: const Icon(Icons.bluetooth_connected_rounded),
                label: const Text('使用此資料連接 BLE'),
              ),
              FilledButton.tonalIcon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('新增使用者'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({
    required this.formKey,
    required this.displayNameController,
    required this.heightController,
    required this.weightController,
    required this.ageController,
    required this.vo2MaxController,
    required this.sex,
    required this.isSaving,
    required this.onSexChanged,
    required this.onSavePressed,
    required this.requiredTextValidator,
    required this.numberValidator,
    required this.optionalVo2MaxValidator,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController displayNameController;
  final TextEditingController heightController;
  final TextEditingController weightController;
  final TextEditingController ageController;
  final TextEditingController vo2MaxController;
  final UserSex sex;
  final bool isSaving;
  final ValueChanged<UserSex> onSexChanged;
  final VoidCallback onSavePressed;
  final FormFieldValidator<String> requiredTextValidator;
  final String? Function(String?, double, double) numberValidator;
  final FormFieldValidator<String> optionalVo2MaxValidator;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '建立使用者',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: '顯示名稱',
                border: OutlineInputBorder(),
              ),
              validator: requiredTextValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '身高 (cm)',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) => numberValidator(value, 80, 250),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '體重 (kg)',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) => numberValidator(value, 20, 250),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '年齡',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) => numberValidator(value, 5, 120),
            ),
            const SizedBox(height: 14),
            Text(
              '生理性別',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UserSex.values.map((UserSex option) {
                return ChoiceChip(
                  selected: sex == option,
                  label: Text(option.label),
                  onSelected: (_) => onSexChanged(option),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: vo2MaxController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'VO2max (選填)',
                border: OutlineInputBorder(),
              ),
              validator: optionalVo2MaxValidator,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isSaving ? null : onSavePressed,
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: const Text('儲存並連接 BLE'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}
