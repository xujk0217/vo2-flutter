import 'package:flutter/material.dart';
import 'package:vo2_flutter/screens/calibration_screen.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';
import 'package:vo2_flutter/screens/dashboard_page.dart';
import 'package:vo2_flutter/user_profile.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const String routeName = '/onboarding';

  @override
  Widget build(BuildContext context) {
    final UserProfile profile = UserProfile.defaults;

    return Scaffold(
      appBar: AppBar(title: const Text('VO2 Motion Monitor')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: <Widget>[
            Text(
              'VO2 Motion Monitor',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '先確認個人資料、連上裝置，再進入校正或即時監測。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 16),
            _HomeActionCard(
              icon: Icons.person_rounded,
              title: '基本資料',
              subtitle: '目前使用預設資料',
              detail: profile.summary,
              primaryLabel: '進入監測與設定',
              onPrimaryPressed: () {
                Navigator.of(context).pushNamed(DashboardPage.routeName);
              },
            ),
            const SizedBox(height: 12),
            _HomeActionCard(
              icon: Icons.bluetooth_connected_rounded,
              title: '裝置連線',
              subtitle: '連接 Classic Bluetooth 裝置接收資料',
              detail: '預設使用 Classic，需要 BLE 測試時可在連線頁切換。',
              primaryLabel: '前往裝置連線',
              onPrimaryPressed: () {
                Navigator.of(context).pushNamed(ConnectionScreen.routeName);
              },
            ),
            const SizedBox(height: 12),
            _HomeActionCard(
              icon: Icons.timer_rounded,
              title: '校正與訓練',
              subtitle: '完成 30 秒靜止校正後開始監測',
              detail: '已熟悉流程時，也可以直接進入即時監測。',
              primaryLabel: '開始校正',
              onPrimaryPressed: () {
                Navigator.of(context).pushNamed(CalibrationScreen.routeName);
              },
              secondaryLabel: '直接監測',
              onSecondaryPressed: () {
                Navigator.of(context).pushNamed(DashboardPage.routeName);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

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
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget leading = DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
          );
          final Widget copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          );
          final Widget actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: <Widget>[
              FilledButton(
                onPressed: onPrimaryPressed,
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondaryPressed != null)
                FilledButton.tonal(
                  onPressed: onSecondaryPressed,
                  child: Text(secondaryLabel!),
                ),
            ],
          );

          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    leading,
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              leading,
              const SizedBox(width: 14),
              Expanded(child: copy),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}
