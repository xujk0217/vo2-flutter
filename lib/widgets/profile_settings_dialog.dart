import 'package:flutter/material.dart';
import 'package:vo2_flutter/user_profile.dart';

class ProfileSettingsDialog extends StatefulWidget {
  const ProfileSettingsDialog({super.key, required this.initialProfile});

  final UserProfile initialProfile;

  @override
  State<ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends State<ProfileSettingsDialog> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _ageController;
  late UserSex _sex;

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController(
      text: widget.initialProfile.heightCm.toStringAsFixed(0),
    );
    _weightController = TextEditingController(
      text: widget.initialProfile.weightKg.toStringAsFixed(0),
    );
    _ageController = TextEditingController(
      text: widget.initialProfile.age.toString(),
    );
    _sex = widget.initialProfile.sex;
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _submit() {
    final double? height = double.tryParse(_heightController.text.trim());
    final double? weight = double.tryParse(_weightController.text.trim());
    final int? age = int.tryParse(_ageController.text.trim());

    if (height == null || weight == null || age == null) {
      return;
    }

    Navigator.of(context).pop(
      UserProfile(
        heightCm: height.clamp(100, 230),
        weightKg: weight.clamp(20, 250),
        age: age.clamp(5, 120),
        sex: _sex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('個人資料設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '身高 (cm)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '體重 (kg)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '年齡',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '性別',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UserSex.values.map((UserSex sex) {
                return ChoiceChip(
                  selected: _sex == sex,
                  label: Text(sex.label),
                  onSelected: (_) {
                    setState(() {
                      _sex = sex;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }
}
