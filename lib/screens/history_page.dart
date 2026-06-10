import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/models/workout_models.dart';
import 'package:vo2_flutter/screens/workout_review_page.dart';
import 'package:vo2_flutter/workout_history_repository.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.historyRepository = const WorkoutHistoryRepository(),
  });

  static const String routeName = '/history';

  final WorkoutHistoryRepository historyRepository;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<WorkoutHistoryEntry> _entries = const <WorkoutHistoryEntry>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEntries());
  }

  Future<void> _loadEntries() async {
    final List<WorkoutHistoryEntry> entries = await widget.historyRepository
        .load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('訓練歷史')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? const _EmptyHistoryState()
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: <Widget>[
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _TrendCard(entries: _entries),
                          const SizedBox(height: 14),
                          ..._entries.map((WorkoutHistoryEntry entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _HistoryTile(entry: entry),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.fitness_center_rounded,
                size: 42,
                color: Color(0xFF0E7490),
              ),
              const SizedBox(height: 14),
              Text(
                '還沒有訓練紀錄',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '完成第一堂即時訓練後，這裡會累積 VO2 趨勢、動作量與教練建議。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.entries});

  final List<WorkoutHistoryEntry> entries;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'VO2 趨勢',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '最近 ${entries.length} 堂訓練',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'VO2 趨勢圖，最近 ${entries.length} 堂訓練',
            image: true,
            child: SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _TrendPainter(entries.reversed.toList()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final WorkoutHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          title: Text(
            '${entry.durationLabel} · ${entry.totalReps} 下',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${entry.profileName} · VO2 ${entry.vo2Avg.toStringAsFixed(1)} · RPE ${entry.rpeAvg == 0 ? '--' : entry.rpeAvg}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(
            context,
          ).pushNamed(WorkoutReviewPage.routeName, arguments: entry.id),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.entries);

  final List<WorkoutHistoryEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i += 1) {
      final double y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (entries.isEmpty) return;
    final double minVo2 = entries
        .map((WorkoutHistoryEntry entry) => entry.vo2Avg)
        .reduce(min);
    final double maxVo2 = entries
        .map((WorkoutHistoryEntry entry) => entry.vo2Avg)
        .reduce(max);
    final double range = max(maxVo2 - minVo2, 1);
    final Path path = Path();
    for (int i = 0; i < entries.length; i += 1) {
      final double x = entries.length == 1
          ? size.width / 2
          : size.width * i / (entries.length - 1);
      final double y =
          size.height - ((entries[i].vo2Avg - minVo2) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF0E7490)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.entries != entries;
  }
}
