import 'package:flutter/material.dart';
import 'package:vo2_flutter/screens/connection_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const String routeName = '/onboarding';

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: '個人資料設定',
      description: '之後會在這裡放第一次進入 App 的個人資料流程。',
      primaryLabel: '前往裝置連線',
      onPrimaryPressed: () {
        Navigator.of(context).pushNamed(ConnectionScreen.routeName);
      },
    );
  }
}

class _FlowScaffold extends StatelessWidget {
  const _FlowScaffold({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimaryPressed,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onPrimaryPressed,
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
