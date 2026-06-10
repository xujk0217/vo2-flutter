import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/screens/history_page.dart';
import 'package:vo2_flutter/screens/live_fitness_page.dart';
import 'package:vo2_flutter/screens/training_home_screen.dart';
import 'package:vo2_flutter/workout_history_repository.dart';
import 'package:vo2_flutter/workout_recommendation.dart';

class WorkoutReviewPage extends StatefulWidget {
  const WorkoutReviewPage({
    super.key,
    this.entry,
    this.historyRepository = const WorkoutHistoryRepository(),
    this.recommendationBuilder = const WorkoutRecommendationBuilder(),
  });

  static const String routeName = '/review';

  final WorkoutHistoryEntry? entry;
  final WorkoutHistoryRepository historyRepository;
  final WorkoutRecommendationBuilder recommendationBuilder;

  @override
  State<WorkoutReviewPage> createState() => _WorkoutReviewPageState();
}

class _WorkoutReviewPageState extends State<WorkoutReviewPage> {
  WorkoutHistoryEntry? _entry;
  bool _loadedRouteArgument = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entry == null && !_loadedRouteArgument) {
      _loadedRouteArgument = true;
      final Object? argument = ModalRoute.of(context)?.settings.arguments;
      unawaited(_loadEntry(argument is String ? argument : null));
    }
  }

  Future<void> _loadEntry(String? id) async {
    final WorkoutHistoryEntry? entry = id == null
        ? await widget.historyRepository.latest()
        : await widget.historyRepository.findById(id);
    if (!mounted) return;
    setState(() {
      _entry = entry;
    });
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutHistoryEntry? entry = _entry;
    return Scaffold(
      appBar: AppBar(title: const Text('訓練回顧')),
      body: SafeArea(
        child: entry == null
            ? const Center(child: Text('還沒有可顯示的訓練摘要。'))
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 900;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: <Widget>[
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: _summaryColumn(context, entry),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: _coachingColumn(context, entry),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    _summaryColumn(context, entry),
                                    const SizedBox(height: 16),
                                    _coachingColumn(context, entry),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _summaryColumn(BuildContext context, WorkoutHistoryEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ReviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '完成一堂 ${entry.durationLabel} 訓練',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${entry.profileName} · ${entry.totalReps} 下有效動作 · 平均 RPE ${entry.rpeAvg == 0 ? '--' : entry.rpeAvg}',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _StatPill(
                    label: '平均 VO2',
                    value: entry.vo2Avg.toStringAsFixed(1),
                  ),
                  _StatPill(
                    label: '最高 VO2',
                    value: entry.vo2Max.toStringAsFixed(1),
                  ),
                  _StatPill(
                    label: 'RPE 區間',
                    value: '${entry.rpeMin}-${entry.rpeMax}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '動作拆解',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...entry.activeMovements.map((MovementSummary movement) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          movement.exerciseLabel,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text('${movement.sets} 組 · ${movement.reps} 下'),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coachingColumn(BuildContext context, WorkoutHistoryEntry entry) {
    final WorkoutRecommendation recommendation = widget.recommendationBuilder
        .build(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ReviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '教練建議',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                recommendation.headline,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 8),
              Text(recommendation.coachingText),
              const SizedBox(height: 10),
              Text(
                recommendation.nextWorkoutText,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReviewCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(LiveFitnessPage.routeName),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('再練一組'),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(HistoryPage.routeName),
                icon: const Icon(Icons.history_rounded),
                label: const Text('查看歷史'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed(TrainingHomeScreen.routeName),
                icon: const Icon(Icons.home_rounded),
                label: const Text('回首頁'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.child});

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
