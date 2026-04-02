import 'dart:math';

import 'package:vo2_flutter/exercise_catalog.dart';

class SensorSample {
  const SensorSample({
    required this.ppg,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.rawLine,
  });

  final List<double> ppg;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final String rawLine;

  double get ppgMeanAbs {
    return ppg
            .map((double value) => value.abs())
            .reduce((double a, double b) => a + b) /
        ppg.length;
  }

  double get accelMagnitude => sqrt((ax * ax) + (ay * ay) + (az * az));

  double get gyroMagnitude => sqrt((gx * gx) + (gy * gy) + (gz * gz));

  static SensorSample? tryParse(String line) {
    final List<String> parts = line.split(',');
    if (parts.length < 15) {
      return null;
    }

    final String firstToken = parts.first.trim().toLowerCase();
    if (firstToken == 'serial') {
      return null;
    }

    final List<double?> ppg = <double?>[
      _parseNumber(parts[4]),
      _parseNumber(parts[5]),
      _parseNumber(parts[6]),
      _parseNumber(parts[7]),
      _parseNumber(parts[8]),
    ];
    final List<double?> imu = <double?>[
      _parseNumber(parts[9]),
      _parseNumber(parts[10]),
      _parseNumber(parts[11]),
      _parseNumber(parts[12]),
      _parseNumber(parts[13]),
      _parseNumber(parts[14]),
    ];

    if (ppg.any((double? value) => value == null) ||
        imu.any((double? value) => value == null)) {
      return null;
    }

    return SensorSample(
      ppg: ppg.cast<double>(),
      ax: imu[0]!,
      ay: imu[1]!,
      az: imu[2]!,
      gx: imu[3]!,
      gy: imu[4]!,
      gz: imu[5]!,
      rawLine: line,
    );
  }

  static double? _parseNumber(String value) {
    final String sanitized = value.trim();
    if (sanitized.isEmpty) {
      return null;
    }
    return double.tryParse(sanitized);
  }
}

class DerivedMetrics {
  const DerivedMetrics({
    required this.estimatedVo2,
    required this.repetitions,
    required this.signalScore,
    required this.motionScore,
  });

  final double estimatedVo2;
  final int repetitions;
  final double signalScore;
  final double motionScore;
}

class PpgFrame {
  const PpgFrame({required this.receivedAt, required this.values});

  final DateTime receivedAt;
  final List<double> values;
}

class MotionEstimator {
  MotionEstimator({required this.exercise});

  final ExerciseType exercise;

  int _repetitions = 0;
  double _motionBaseline = 0;
  DateTime? _lastRepAt;

  DerivedMetrics absorb(SensorSample sample) {
    final DateTime now = DateTime.now();
    final double motionScore =
        sample.accelMagnitude + (sample.gyroMagnitude * 0.02);
    _motionBaseline = _motionBaseline == 0
        ? motionScore
        : (_motionBaseline * 0.9) + (motionScore * 0.1);

    final double threshold = max(
      _motionBaseline * 1.12,
      _motionBaseline + 0.35,
    );
    if (motionScore > threshold &&
        (_lastRepAt == null ||
            now.difference(_lastRepAt!).inMilliseconds > 650)) {
      _repetitions += 1;
      _lastRepAt = now;
    }

    final double signalScore = log(sample.ppgMeanAbs + 1) / ln10;
    final double estimatedVo2 =
        (18 + (signalScore * 4.8) + (max(motionScore - 0.8, 0) * 1.35)).clamp(
          18.0,
          65.0,
        );

    return DerivedMetrics(
      estimatedVo2: estimatedVo2,
      repetitions: _repetitions,
      signalScore: signalScore,
      motionScore: motionScore,
    );
  }
}
