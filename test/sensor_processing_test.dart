import 'package:flutter_test/flutter_test.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/sensor_processing.dart';

void main() {
  group('SensorSample.tryParse', () {
    test('parses a valid CSV sensor line', () {
      const String line =
          '1,2,3,4,100,200,300,400,500,0.1,0.2,0.3,1.1,1.2,1.3';

      final SensorSample? sample = SensorSample.tryParse(line);

      expect(sample, isNotNull);
      expect(sample!.ppg, <double>[100, 200, 300, 400, 500]);
      expect(sample.ax, 0.1);
      expect(sample.ay, 0.2);
      expect(sample.az, 0.3);
      expect(sample.gx, 1.1);
      expect(sample.gy, 1.2);
      expect(sample.gz, 1.3);
      expect(sample.rawLine, line);
    });

    test('returns null for serial header lines', () {
      const String line =
          'serial,2,3,4,100,200,300,400,500,0.1,0.2,0.3,1.1,1.2,1.3';

      expect(SensorSample.tryParse(line), isNull);
    });

    test('returns null when required numeric fields are invalid', () {
      const String line =
          '1,2,3,4,100,200,300,400,500,0.1,0.2,0.3,1.1,1.2,not-a-number';

      expect(SensorSample.tryParse(line), isNull);
    });

    test('returns null when line is too short', () {
      const String line = '1,2,3';

      expect(SensorSample.tryParse(line), isNull);
    });
  });

  group('CsvSensorSampleParser', () {
    test('parses valid payload through parser seam', () {
      const CsvSensorSampleParser parser = CsvSensorSampleParser();
      const String line =
          '1,2,3,4,100,200,300,400,500,0.1,0.2,0.3,1.1,1.2,1.3';

      final SensorSample? sample = parser.tryParse(line);

      expect(sample, isNotNull);
      expect(sample!.rawLine, line);
      expect(sample.ppg.length, 5);
    });
  });

  group('MotionEstimator', () {
    test('keeps repetition count when motion stays below threshold', () {
      final MotionEstimator estimator = MotionEstimator(
        exercise: exerciseCatalog.first,
      );

      const SensorSample sample = SensorSample(
        ppg: <double>[10, 10, 10, 10, 10],
        ax: 0.1,
        ay: 0.1,
        az: 0.1,
        gx: 0.1,
        gy: 0.1,
        gz: 0.1,
        rawLine: 'raw',
      );

      final DerivedMetrics first = estimator.absorb(sample);
      final DerivedMetrics second = estimator.absorb(sample);

      expect(first.repetitions, 0);
      expect(second.repetitions, 0);
      expect(second.signalScore, greaterThanOrEqualTo(0));
    });
  });
}
