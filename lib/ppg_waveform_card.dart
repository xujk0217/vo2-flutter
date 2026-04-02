import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/sensor_processing.dart';

class PpgWaveformCard extends StatelessWidget {
  const PpgWaveformCard({
    super.key,
    required this.frames,
    required this.selectedChannel,
    required this.onChannelSelected,
    required this.window,
  });

  final List<PpgFrame> frames;
  final int selectedChannel;
  final ValueChanged<int> onChannelSelected;
  final Duration window;

  static const List<_TraceStyle> _styles = <_TraceStyle>[
    _TraceStyle('PPG A', Color(0xFF0EA5E9)),
    _TraceStyle('PPG B', Color(0xFF22C55E)),
    _TraceStyle('PPG C', Color(0xFFF59E0B)),
    _TraceStyle('PPG D', Color(0xFFF43F5E)),
    _TraceStyle('PPG E', Color(0xFFA855F7)),
  ];

  @override
  Widget build(BuildContext context) {
    final List<PpgFrame> recentFrames = _recentFrames();
    final bool hasData = recentFrames.isNotEmpty;
    final List<double> selectedTrace = _extractTrace(
      recentFrames,
      selectedChannel,
    );
    final double selectedAverage = _average(selectedTrace);

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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '即時 PPG 波形',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '固定顯示最近 ${window.inSeconds} 秒資料',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List<Widget>.generate(_styles.length, (int index) {
              final _TraceStyle style = _styles[index];
              return ChoiceChip(
                selected: selectedChannel == index,
                label: Text(style.label),
                labelStyle: TextStyle(
                  color: selectedChannel == index
                      ? Colors.white
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: style.color,
                backgroundColor: style.color.withValues(alpha: 0.08),
                side: BorderSide(color: style.color.withValues(alpha: 0.2)),
                onSelected: (_) => onChannelSelected(index),
              );
            }),
          ),
          const SizedBox(height: 16),
          _WaveformPanel(
            title: '${_styles[selectedChannel].label} 單波段',
            subtitle: hasData
                ? '10 秒平均值 ${selectedAverage.toStringAsFixed(0)}'
                : '等待 PPG 資料中',
            child: SizedBox(
              height: 200,
              child: hasData
                  ? CustomPaint(
                      painter: _CenteredSingleWavePainter(
                        frames: recentFrames,
                        channelIndex: selectedChannel,
                        color: _styles[selectedChannel].color,
                        window: window,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : const _WavePlaceholder(),
            ),
          ),
          const SizedBox(height: 16),
          _WaveformPanel(
            title: '全部波段總覽',
            subtitle: hasData ? '全部波段皆以各自 10 秒平均值為中心' : '等待 PPG 資料中',
            child: SizedBox(
              height: 260,
              child: hasData
                  ? CustomPaint(
                      painter: _CenteredOverlayWavePainter(
                        frames: recentFrames,
                        styles: _styles,
                        window: window,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : const _WavePlaceholder(),
            ),
          ),
        ],
      ),
    );
  }

  List<PpgFrame> _recentFrames() {
    if (frames.isEmpty) {
      return const <PpgFrame>[];
    }

    final DateTime latest = frames.last.receivedAt;
    final DateTime cutoff = latest.subtract(window);
    return frames
        .where((PpgFrame frame) => !frame.receivedAt.isBefore(cutoff))
        .toList();
  }

  List<double> _extractTrace(List<PpgFrame> currentFrames, int channelIndex) {
    return currentFrames
        .where((PpgFrame frame) => frame.values.length > channelIndex)
        .map((PpgFrame frame) => frame.values[channelIndex])
        .toList();
  }

  double _average(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((double a, double b) => a + b) / values.length;
  }
}

class _WaveformPanel extends StatelessWidget {
  const _WaveformPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _WavePlaceholder extends StatelessWidget {
  const _WavePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '等待 PPG 資料中',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class _CenteredSingleWavePainter extends CustomPainter {
  const _CenteredSingleWavePainter({
    required this.frames,
    required this.channelIndex,
    required this.color,
    required this.window,
  });

  final List<PpgFrame> frames;
  final int channelIndex;
  final Color color;
  final Duration window;

  @override
  void paint(Canvas canvas, Size size) {
    final List<_WavePoint> points = _buildCenteredPoints(
      frames,
      channelIndex,
      window,
    );
    _paintGrid(canvas, size, midLines: 4);
    _paintCenteredWave(
      canvas: canvas,
      size: size,
      points: points,
      lines: <Color>[color],
      drawLabels: false,
    );
  }

  @override
  bool shouldRepaint(covariant _CenteredSingleWavePainter oldDelegate) {
    return oldDelegate.frames != frames ||
        oldDelegate.channelIndex != channelIndex;
  }
}

class _CenteredOverlayWavePainter extends CustomPainter {
  const _CenteredOverlayWavePainter({
    required this.frames,
    required this.styles,
    required this.window,
  });

  final List<PpgFrame> frames;
  final List<_TraceStyle> styles;
  final Duration window;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size, midLines: 4);

    const double legendTop = 8;
    double legendLeft = 14;

    for (int i = 0; i < styles.length; i += 1) {
      final _TraceStyle style = styles[i];
      final List<_WavePoint> points = _buildCenteredPoints(frames, i, window);

      _paintCenteredWave(
        canvas: canvas,
        size: size,
        points: points,
        lines: <Color>[style.color],
        drawLabels: false,
      );

      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: style.label,
          style: TextStyle(
            color: style.color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.drawCircle(
        Offset(legendLeft + 4, legendTop + 6),
        4,
        Paint()..color = style.color,
      );
      painter.paint(canvas, Offset(legendLeft + 12, legendTop));
      legendLeft += painter.width + 36;
    }
  }

  @override
  bool shouldRepaint(covariant _CenteredOverlayWavePainter oldDelegate) {
    return oldDelegate.frames != frames;
  }
}

List<_WavePoint> _buildCenteredPoints(
  List<PpgFrame> frames,
  int channelIndex,
  Duration window,
) {
  if (frames.isEmpty) {
    return const <_WavePoint>[];
  }

  final List<PpgFrame> filtered = frames
      .where((PpgFrame frame) => frame.values.length > channelIndex)
      .toList();
  if (filtered.isEmpty) {
    return const <_WavePoint>[];
  }

  final double average =
      filtered
          .map((PpgFrame frame) => frame.values[channelIndex])
          .reduce((double a, double b) => a + b) /
      filtered.length;
  final DateTime latest = filtered.last.receivedAt;
  final DateTime start = latest.subtract(window);
  final double windowMs = max(window.inMilliseconds.toDouble(), 1);

  return filtered.map((PpgFrame frame) {
    final double xRatio =
        frame.receivedAt.difference(start).inMilliseconds / windowMs;
    return _WavePoint(xRatio.clamp(0, 1), frame.values[channelIndex] - average);
  }).toList();
}

void _paintGrid(Canvas canvas, Size size, {required int midLines}) {
  final Paint background = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  final RRect frame = RRect.fromRectAndRadius(
    Offset.zero & size,
    const Radius.circular(14),
  );
  canvas.drawRRect(frame, background);

  final Paint grid = Paint()
    ..color = const Color(0xFFE2E8F0)
    ..strokeWidth = 1;
  final double midY = size.height / 2;

  canvas.drawLine(Offset(0, midY), Offset(size.width, midY), grid);
  for (int i = 1; i <= midLines; i += 1) {
    final double x = size.width * i / (midLines + 1);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
}

void _paintCenteredWave({
  required Canvas canvas,
  required Size size,
  required List<_WavePoint> points,
  required List<Color> lines,
  required bool drawLabels,
}) {
  if (points.length < 2) {
    return;
  }

  final double maxAbs = points
      .map((_WavePoint point) => point.y.abs())
      .fold<double>(1, max);
  final Path path = Path();

  for (int i = 0; i < points.length; i += 1) {
    final _WavePoint point = points[i];
    final double x = point.x * size.width;
    final double y =
        (size.height / 2) - ((point.y / maxAbs) * (size.height * 0.38));
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }

  final Paint paint = Paint()
    ..color = lines.first
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  canvas.drawPath(path, paint);

  if (drawLabels) {
    return;
  }
}

class _WavePoint {
  const _WavePoint(this.x, this.y);

  final double x;
  final double y;
}

class _TraceStyle {
  const _TraceStyle(this.label, this.color);

  final String label;
  final Color color;
}
