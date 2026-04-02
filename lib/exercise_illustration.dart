import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';

class ExerciseIllustrationCard extends StatelessWidget {
  const ExerciseIllustrationCard({super.key, required this.exercise});

  final ExerciseType exercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[exercise.startColor, exercise.endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: exercise.endColor.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _BackdropPainter(accent: exercise.endColor),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(exercise.icon, color: Colors.white, size: 28),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  exercise.label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exercise.caption,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _AthletePainter(pose: exercise.pose),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.22), 34, halo);
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.8), 52, halo);
    canvas.drawCircle(Offset(size.width * 0.72, size.height * 0.18), 18, halo);

    final Paint floor = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.86),
        width: size.width * 0.72,
        height: size.height * 0.18,
      ),
      floor,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

class _AthletePainter extends CustomPainter {
  const _AthletePainter({required this.pose});

  final ExercisePose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final _PosePoints points = _posePointsFor(size);
    final Paint body = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint joint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;

    canvas.drawLine(points.neck, points.hip, body);
    _drawLimb(canvas, body, points.neck, points.leftElbow, points.leftHand);
    _drawLimb(canvas, body, points.neck, points.rightElbow, points.rightHand);
    _drawLimb(canvas, body, points.hip, points.leftKnee, points.leftFoot);
    _drawLimb(canvas, body, points.hip, points.rightKnee, points.rightFoot);

    canvas.drawCircle(points.headCenter, size.width * 0.055, joint);
    for (final Offset point in <Offset>[
      points.neck,
      points.hip,
      points.leftElbow,
      points.rightElbow,
      points.leftKnee,
      points.rightKnee,
    ]) {
      canvas.drawCircle(point, 5.5, joint);
    }
  }

  void _drawLimb(Canvas canvas, Paint paint, Offset a, Offset b, Offset c) {
    canvas.drawLine(a, b, paint);
    canvas.drawLine(b, c, paint);
  }

  _PosePoints _posePointsFor(Size size) {
    Offset point(double x, double y) => Offset(size.width * x, size.height * y);

    switch (pose) {
      case ExercisePose.jumpingJack:
        return _PosePoints(
          headCenter: point(0.50, 0.16),
          neck: point(0.50, 0.28),
          hip: point(0.50, 0.52),
          leftElbow: point(0.37, 0.22),
          leftHand: point(0.24, 0.14),
          rightElbow: point(0.63, 0.22),
          rightHand: point(0.76, 0.14),
          leftKnee: point(0.41, 0.69),
          leftFoot: point(0.28, 0.88),
          rightKnee: point(0.59, 0.69),
          rightFoot: point(0.72, 0.88),
        );
      case ExercisePose.squat:
        return _PosePoints(
          headCenter: point(0.48, 0.18),
          neck: point(0.48, 0.30),
          hip: point(0.48, 0.54),
          leftElbow: point(0.61, 0.38),
          leftHand: point(0.73, 0.40),
          rightElbow: point(0.58, 0.43),
          rightHand: point(0.72, 0.48),
          leftKnee: point(0.36, 0.70),
          leftFoot: point(0.50, 0.88),
          rightKnee: point(0.62, 0.70),
          rightFoot: point(0.74, 0.88),
        );
      case ExercisePose.lunge:
        return _PosePoints(
          headCenter: point(0.46, 0.17),
          neck: point(0.46, 0.29),
          hip: point(0.48, 0.52),
          leftElbow: point(0.37, 0.38),
          leftHand: point(0.32, 0.52),
          rightElbow: point(0.58, 0.36),
          rightHand: point(0.65, 0.23),
          leftKnee: point(0.36, 0.69),
          leftFoot: point(0.28, 0.88),
          rightKnee: point(0.64, 0.62),
          rightFoot: point(0.74, 0.88),
        );
      case ExercisePose.pushUp:
        return _PosePoints(
          headCenter: point(0.70, 0.45),
          neck: point(0.60, 0.50),
          hip: point(0.38, 0.56),
          leftElbow: point(0.56, 0.66),
          leftHand: point(0.66, 0.80),
          rightElbow: point(0.46, 0.54),
          rightHand: point(0.61, 0.70),
          leftKnee: point(0.20, 0.62),
          leftFoot: point(0.08, 0.66),
          rightKnee: point(0.18, 0.60),
          rightFoot: point(0.04, 0.62),
        );
      case ExercisePose.sitUp:
        return _PosePoints(
          headCenter: point(0.64, 0.43),
          neck: point(0.57, 0.49),
          hip: point(0.39, 0.63),
          leftElbow: point(0.64, 0.37),
          leftHand: point(0.72, 0.30),
          rightElbow: point(0.52, 0.58),
          rightHand: point(0.62, 0.64),
          leftKnee: point(0.26, 0.70),
          leftFoot: point(0.18, 0.86),
          rightKnee: point(0.27, 0.58),
          rightFoot: point(0.15, 0.72),
        );
      case ExercisePose.highKnees:
        return _PosePoints(
          headCenter: point(0.50, 0.16),
          neck: point(0.50, 0.28),
          hip: point(0.50, 0.52),
          leftElbow: point(0.38, 0.34),
          leftHand: point(0.30, 0.26),
          rightElbow: point(0.64, 0.34),
          rightHand: point(0.72, 0.44),
          leftKnee: point(0.38, 0.60),
          leftFoot: point(0.30, 0.84),
          rightKnee: point(0.64, 0.71),
          rightFoot: point(0.74, 0.89),
        );
      case ExercisePose.burpee:
        return _PosePoints(
          headCenter: point(0.58, 0.29),
          neck: point(0.54, 0.38),
          hip: point(0.42, 0.59),
          leftElbow: point(0.48, 0.55),
          leftHand: point(0.58, 0.79),
          rightElbow: point(0.37, 0.55),
          rightHand: point(0.24, 0.80),
          leftKnee: point(0.50, 0.73),
          leftFoot: point(0.60, 0.90),
          rightKnee: point(0.34, 0.72),
          rightFoot: point(0.26, 0.89),
        );
      case ExercisePose.mountainClimber:
        return _PosePoints(
          headCenter: point(0.70, 0.34),
          neck: point(0.62, 0.40),
          hip: point(0.42, 0.56),
          leftElbow: point(0.54, 0.56),
          leftHand: point(0.67, 0.74),
          rightElbow: point(0.44, 0.46),
          rightHand: point(0.58, 0.66),
          leftKnee: point(0.34, 0.72),
          leftFoot: point(0.26, 0.89),
          rightKnee: point(0.20, 0.56),
          rightFoot: point(0.06, 0.62),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _AthletePainter oldDelegate) {
    return oldDelegate.pose != pose;
  }
}

class _PosePoints {
  const _PosePoints({
    required this.headCenter,
    required this.neck,
    required this.hip,
    required this.leftElbow,
    required this.leftHand,
    required this.rightElbow,
    required this.rightHand,
    required this.leftKnee,
    required this.leftFoot,
    required this.rightKnee,
    required this.rightFoot,
  });

  final Offset headCenter;
  final Offset neck;
  final Offset hip;
  final Offset leftElbow;
  final Offset leftHand;
  final Offset rightElbow;
  final Offset rightHand;
  final Offset leftKnee;
  final Offset leftFoot;
  final Offset rightKnee;
  final Offset rightFoot;
}
