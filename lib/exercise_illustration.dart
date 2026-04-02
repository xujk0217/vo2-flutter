import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';

class ExerciseIllustrationCard extends StatefulWidget {
  const ExerciseIllustrationCard({
    super.key,
    required this.exercise,
    required this.onRepCompleted,
  });

  final ExerciseType exercise;
  final VoidCallback onRepCompleted;

  @override
  State<ExerciseIllustrationCard> createState() =>
      _ExerciseIllustrationCardState();
}

class _ExerciseIllustrationCardState extends State<ExerciseIllustrationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1600),
          )
          ..addStatusListener((AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              widget.onRepCompleted();
              _controller.reverse();
            } else if (status == AnimationStatus.dismissed) {
              _controller.forward();
            }
          })
          ..forward();
  }

  @override
  void didUpdateWidget(covariant ExerciseIllustrationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.pose != widget.exercise.pose) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                widget.exercise.startColor,
                widget.exercise.endColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.exercise.endColor.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _BackdropPainter(accent: widget.exercise.endColor),
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
                    child: Icon(
                      widget.exercise.icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.exercise.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.exercise.caption,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '示意圖會循環動作並同步累加次數',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _AthletePainter(
                          pose: widget.exercise.pose,
                          progress: Curves.easeInOut.transform(
                            _controller.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
  const _AthletePainter({required this.pose, required this.progress});

  final ExercisePose pose;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final _PosePoints start = _startPose(size);
    final _PosePoints end = _endPose(size);
    final _PosePoints points = _PosePoints.lerp(start, end, progress);

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

    _drawDumbbell(canvas, points.leftHand, points.leftGripAngle);
    _drawDumbbell(canvas, points.rightHand, points.rightGripAngle);
  }

  void _drawLimb(Canvas canvas, Paint paint, Offset a, Offset b, Offset c) {
    canvas.drawLine(a, b, paint);
    canvas.drawLine(b, c, paint);
  }

  void _drawDumbbell(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final Paint handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint plate = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;

    canvas.drawLine(const Offset(-11, 0), const Offset(11, 0), handle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-16, 0), width: 6, height: 18),
        const Radius.circular(3),
      ),
      plate,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(16, 0), width: 6, height: 18),
        const Radius.circular(3),
      ),
      plate,
    );
    canvas.restore();
  }

  _PosePoints _startPose(Size size) {
    return _posePair(size).$1;
  }

  _PosePoints _endPose(Size size) {
    return _posePair(size).$2;
  }

  (_PosePoints, _PosePoints) _posePair(Size size) {
    Offset point(double x, double y) => Offset(size.width * x, size.height * y);

    switch (pose) {
      case ExercisePose.dumbbellBenchPress:
        return (
          _PosePoints(
            headCenter: point(0.64, 0.41),
            neck: point(0.57, 0.47),
            hip: point(0.38, 0.58),
            leftElbow: point(0.50, 0.39),
            leftHand: point(0.48, 0.28),
            rightElbow: point(0.66, 0.39),
            rightHand: point(0.68, 0.28),
            leftKnee: point(0.22, 0.62),
            leftFoot: point(0.10, 0.72),
            rightKnee: point(0.18, 0.50),
            rightFoot: point(0.06, 0.54),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.64, 0.41),
            neck: point(0.57, 0.47),
            hip: point(0.38, 0.58),
            leftElbow: point(0.52, 0.33),
            leftHand: point(0.52, 0.16),
            rightElbow: point(0.64, 0.33),
            rightHand: point(0.64, 0.16),
            leftKnee: point(0.22, 0.62),
            leftFoot: point(0.10, 0.72),
            rightKnee: point(0.18, 0.50),
            rightFoot: point(0.06, 0.54),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.singleArmDumbbellRow:
        return (
          _PosePoints(
            headCenter: point(0.56, 0.16),
            neck: point(0.54, 0.28),
            hip: point(0.45, 0.52),
            leftElbow: point(0.32, 0.58),
            leftHand: point(0.24, 0.82),
            rightElbow: point(0.62, 0.40),
            rightHand: point(0.68, 0.28),
            leftKnee: point(0.34, 0.70),
            leftFoot: point(0.24, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.72, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: 0,
          ),
          _PosePoints(
            headCenter: point(0.56, 0.16),
            neck: point(0.54, 0.28),
            hip: point(0.45, 0.52),
            leftElbow: point(0.34, 0.54),
            leftHand: point(0.24, 0.74),
            rightElbow: point(0.62, 0.40),
            rightHand: point(0.68, 0.28),
            leftKnee: point(0.34, 0.70),
            leftFoot: point(0.24, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.72, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: 0,
          ),
        );
      case ExercisePose.dumbbellShoulderPress:
        return (
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.38, 0.36),
            leftHand: point(0.36, 0.24),
            rightElbow: point(0.62, 0.36),
            rightHand: point(0.64, 0.24),
            leftKnee: point(0.42, 0.70),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.40, 0.28),
            leftHand: point(0.38, 0.12),
            rightElbow: point(0.60, 0.28),
            rightHand: point(0.62, 0.12),
            leftKnee: point(0.42, 0.70),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellBicepsCurl:
        return (
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.52),
            leftElbow: point(0.42, 0.44),
            leftHand: point(0.38, 0.58),
            rightElbow: point(0.58, 0.44),
            rightHand: point(0.62, 0.58),
            leftKnee: point(0.43, 0.70),
            leftFoot: point(0.38, 0.90),
            rightKnee: point(0.57, 0.70),
            rightFoot: point(0.62, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.52),
            leftElbow: point(0.42, 0.44),
            leftHand: point(0.40, 0.26),
            rightElbow: point(0.58, 0.44),
            rightHand: point(0.60, 0.26),
            leftKnee: point(0.43, 0.70),
            leftFoot: point(0.38, 0.90),
            rightKnee: point(0.57, 0.70),
            rightFoot: point(0.62, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellTricepsExtension:
        return (
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.44, 0.26),
            leftHand: point(0.42, 0.18),
            rightElbow: point(0.56, 0.26),
            rightHand: point(0.58, 0.18),
            leftKnee: point(0.42, 0.70),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.47, 0.20),
            leftHand: point(0.48, 0.08),
            rightElbow: point(0.53, 0.20),
            rightHand: point(0.52, 0.08),
            leftKnee: point(0.42, 0.70),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellSquat:
        return (
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.49),
            leftElbow: point(0.40, 0.44),
            leftHand: point(0.36, 0.52),
            rightElbow: point(0.60, 0.44),
            rightHand: point(0.64, 0.52),
            leftKnee: point(0.44, 0.62),
            leftFoot: point(0.34, 0.90),
            rightKnee: point(0.56, 0.62),
            rightFoot: point(0.66, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.40, 0.46),
            leftHand: point(0.34, 0.60),
            rightElbow: point(0.60, 0.46),
            rightHand: point(0.66, 0.60),
            leftKnee: point(0.38, 0.71),
            leftFoot: point(0.31, 0.90),
            rightKnee: point(0.62, 0.71),
            rightFoot: point(0.69, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellRomanianDeadlift:
        return (
          _PosePoints(
            headCenter: point(0.52, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.48, 0.50),
            leftElbow: point(0.42, 0.42),
            leftHand: point(0.38, 0.58),
            rightElbow: point(0.54, 0.42),
            rightHand: point(0.58, 0.58),
            leftKnee: point(0.42, 0.68),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.68),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.54, 0.18),
            neck: point(0.52, 0.30),
            hip: point(0.46, 0.55),
            leftElbow: point(0.42, 0.46),
            leftHand: point(0.36, 0.72),
            rightElbow: point(0.52, 0.46),
            rightHand: point(0.56, 0.72),
            leftKnee: point(0.42, 0.72),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.72),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellCrunch:
        return (
          _PosePoints(
            headCenter: point(0.60, 0.50),
            neck: point(0.54, 0.55),
            hip: point(0.40, 0.64),
            leftElbow: point(0.58, 0.44),
            leftHand: point(0.64, 0.34),
            rightElbow: point(0.50, 0.60),
            rightHand: point(0.56, 0.64),
            leftKnee: point(0.26, 0.70),
            leftFoot: point(0.18, 0.88),
            rightKnee: point(0.28, 0.58),
            rightFoot: point(0.16, 0.73),
            leftGripAngle: pi / 5,
            rightGripAngle: pi / 5,
          ),
          _PosePoints(
            headCenter: point(0.66, 0.42),
            neck: point(0.58, 0.48),
            hip: point(0.40, 0.62),
            leftElbow: point(0.60, 0.36),
            leftHand: point(0.68, 0.26),
            rightElbow: point(0.52, 0.56),
            rightHand: point(0.61, 0.60),
            leftKnee: point(0.26, 0.70),
            leftFoot: point(0.18, 0.88),
            rightKnee: point(0.28, 0.58),
            rightFoot: point(0.16, 0.73),
            leftGripAngle: pi / 5,
            rightGripAngle: pi / 5,
          ),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _AthletePainter oldDelegate) {
    return oldDelegate.pose != pose || oldDelegate.progress != progress;
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
    this.leftGripAngle = 0,
    this.rightGripAngle = 0,
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
  final double leftGripAngle;
  final double rightGripAngle;

  factory _PosePoints.lerp(_PosePoints a, _PosePoints b, double t) {
    return _PosePoints(
      headCenter: Offset.lerp(a.headCenter, b.headCenter, t)!,
      neck: Offset.lerp(a.neck, b.neck, t)!,
      hip: Offset.lerp(a.hip, b.hip, t)!,
      leftElbow: Offset.lerp(a.leftElbow, b.leftElbow, t)!,
      leftHand: Offset.lerp(a.leftHand, b.leftHand, t)!,
      rightElbow: Offset.lerp(a.rightElbow, b.rightElbow, t)!,
      rightHand: Offset.lerp(a.rightHand, b.rightHand, t)!,
      leftKnee: Offset.lerp(a.leftKnee, b.leftKnee, t)!,
      leftFoot: Offset.lerp(a.leftFoot, b.leftFoot, t)!,
      rightKnee: Offset.lerp(a.rightKnee, b.rightKnee, t)!,
      rightFoot: Offset.lerp(a.rightFoot, b.rightFoot, t)!,
      leftGripAngle:
          a.leftGripAngle + ((b.leftGripAngle - a.leftGripAngle) * t),
      rightGripAngle:
          a.rightGripAngle + ((b.rightGripAngle - a.rightGripAngle) * t),
    );
  }
}
