import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';

class ExerciseIllustrationCard extends StatefulWidget {
  const ExerciseIllustrationCard({
    super.key,
    required this.exercise,
    required this.isActive,
    required this.onRepCompleted,
  });

  final ExerciseType exercise;
  final bool isActive;
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
        )..addStatusListener((AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            if (widget.isActive) {
              widget.onRepCompleted();
              _controller.reverse();
            }
          } else if (status == AnimationStatus.dismissed) {
            if (widget.isActive) {
              _controller.forward();
            }
          }
        });
    if (widget.isActive) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ExerciseIllustrationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.pose != widget.exercise.pose) {
      _controller
        ..value = 0
        ..stop();
      if (widget.isActive) {
        _controller.forward();
      }
    } else if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _controller
          ..value = 0
          ..forward();
      } else {
        _controller
          ..stop()
          ..value = 0;
      }
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
                      widget.isActive
                          ? '藍牙已連線，示意圖會循環動作並同步累加次數'
                          : '等待藍牙連線後開始動作與計次',
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

    _drawEquipment(canvas, size, points);

    final Offset leftShoulder = points.neck.translate(
      -size.width * 0.065,
      size.height * 0.02,
    );
    final Offset rightShoulder = points.neck.translate(
      size.width * 0.065,
      size.height * 0.02,
    );
    final Offset leftHip = points.hip.translate(-size.width * 0.045, 0);
    final Offset rightHip = points.hip.translate(size.width * 0.045, 0);
    final double upperArmLength = size.height * 0.16;
    final double lowerArmLength = size.height * 0.15;
    final double upperLegLength = size.height * 0.22;
    final double lowerLegLength = size.height * 0.21;
    _ResolvedLimb leftArm = _ResolvedLimb(
      joint: _solveJoint(
        leftShoulder,
        points.leftHand,
        upperArmLength,
        lowerArmLength,
        points.leftElbow,
      ),
      end: points.leftHand,
    );
    _ResolvedLimb rightArm = _ResolvedLimb(
      joint: _solveJoint(
        rightShoulder,
        points.rightHand,
        upperArmLength,
        lowerArmLength,
        points.rightElbow,
      ),
      end: points.rightHand,
    );
    _ResolvedLimb leftLeg = _ResolvedLimb(
      joint: _solveJoint(
        leftHip,
        points.leftFoot,
        upperLegLength,
        lowerLegLength,
        points.leftKnee,
      ),
      end: points.leftFoot,
    );
    _ResolvedLimb rightLeg = _ResolvedLimb(
      joint: _solveJoint(
        rightHip,
        points.rightFoot,
        upperLegLength,
        lowerLegLength,
        points.rightKnee,
      ),
      end: points.rightFoot,
    );

    switch (pose) {
      case ExercisePose.dumbbellSquat:
        leftLeg = _resolveGuidedLimb(
          leftHip,
          points.leftKnee,
          points.leftFoot,
          upperLegLength,
          lowerLegLength,
        );
        rightLeg = _resolveGuidedLimb(
          rightHip,
          points.rightKnee,
          points.rightFoot,
          upperLegLength,
          lowerLegLength,
        );
        break;
      case ExercisePose.singleArmDumbbellRow:
      case ExercisePose.dumbbellBicepsCurl:
        leftArm = _resolveGuidedLimb(
          leftShoulder,
          points.leftElbow,
          points.leftHand,
          upperArmLength,
          lowerArmLength,
        );
        rightArm = _resolveGuidedLimb(
          rightShoulder,
          points.rightElbow,
          points.rightHand,
          upperArmLength,
          lowerArmLength,
        );
        break;
      case ExercisePose.dumbbellBenchPress:
      case ExercisePose.dumbbellShoulderPress:
      case ExercisePose.dumbbellTricepsExtension:
      case ExercisePose.dumbbellRomanianDeadlift:
      case ExercisePose.dumbbellCrunch:
        break;
    }

    _drawTorso(canvas, leftShoulder, rightShoulder, leftHip, rightHip);
    _drawStyledLimb(
      canvas,
      leftShoulder,
      leftArm.joint,
      leftArm.end,
      width: 15,
    );
    _drawStyledLimb(
      canvas,
      rightShoulder,
      rightArm.joint,
      rightArm.end,
      width: 15,
    );
    _drawStyledLimb(canvas, leftHip, leftLeg.joint, leftLeg.end, width: 17);
    _drawStyledLimb(canvas, rightHip, rightLeg.joint, rightLeg.end, width: 17);

    _drawHead(canvas, points.headCenter, size.width * 0.06);
    _drawHand(canvas, leftArm.end);
    _drawHand(canvas, rightArm.end);
    _drawFoot(canvas, leftLeg.end, left: true);
    _drawFoot(canvas, rightLeg.end, left: false);

    for (final Offset point in <Offset>[
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
      leftArm.joint,
      rightArm.joint,
      leftLeg.joint,
      rightLeg.joint,
    ]) {
      _drawJoint(canvas, point);
    }

    _drawWeights(
      canvas,
      leftHand: leftArm.end,
      rightHand: rightArm.end,
      leftGripAngle: points.leftGripAngle,
      rightGripAngle: points.rightGripAngle,
    );
  }

  void _drawEquipment(Canvas canvas, Size size, _PosePoints points) {
    final Paint frame = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final Paint fill = Paint()
      ..color = const Color(0xFFF8FAFC).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    switch (pose) {
      case ExercisePose.dumbbellBenchPress:
        final RRect benchPad = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * 0.34, size.height * 0.60),
            width: size.width * 0.40,
            height: size.height * 0.09,
          ),
          const Radius.circular(18),
        );
        canvas.drawRRect(benchPad, fill);
        canvas.drawRRect(benchPad, frame);
        canvas.drawLine(
          Offset(size.width * 0.26, size.height * 0.64),
          Offset(size.width * 0.22, size.height * 0.82),
          frame,
        );
        canvas.drawLine(
          Offset(size.width * 0.42, size.height * 0.64),
          Offset(size.width * 0.46, size.height * 0.82),
          frame,
        );
        break;
      case ExercisePose.singleArmDumbbellRow:
        final RRect supportBench = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * 0.50, size.height * 0.57),
            width: size.width * 0.26,
            height: size.height * 0.08,
          ),
          const Radius.circular(16),
        );
        canvas.drawRRect(supportBench, fill);
        canvas.drawRRect(supportBench, frame);
        canvas.drawLine(
          Offset(size.width * 0.44, size.height * 0.61),
          Offset(size.width * 0.40, size.height * 0.80),
          frame,
        );
        canvas.drawLine(
          Offset(size.width * 0.56, size.height * 0.61),
          Offset(size.width * 0.60, size.height * 0.80),
          frame,
        );
        break;
      case ExercisePose.dumbbellShoulderPress:
      case ExercisePose.dumbbellTricepsExtension:
        final RRect seat = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * 0.50, size.height * 0.62),
            width: size.width * 0.24,
            height: size.height * 0.08,
          ),
          const Radius.circular(14),
        );
        canvas.drawRRect(seat, fill);
        canvas.drawRRect(seat, frame);
        canvas.drawLine(
          Offset(size.width * 0.44, size.height * 0.66),
          Offset(size.width * 0.44, size.height * 0.84),
          frame,
        );
        canvas.drawLine(
          Offset(size.width * 0.56, size.height * 0.66),
          Offset(size.width * 0.56, size.height * 0.84),
          frame,
        );
        break;
      case ExercisePose.dumbbellCrunch:
        final RRect mat = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * 0.40, size.height * 0.72),
            width: size.width * 0.52,
            height: size.height * 0.12,
          ),
          const Radius.circular(24),
        );
        canvas.drawRRect(mat, fill);
        canvas.drawRRect(mat, frame);
        break;
      case ExercisePose.dumbbellBicepsCurl:
      case ExercisePose.dumbbellSquat:
      case ExercisePose.dumbbellRomanianDeadlift:
        final Paint guide = Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(size.width * 0.18, size.height * 0.74),
          Offset(size.width * 0.82, size.height * 0.74),
          guide,
        );
        break;
    }
  }

  void _drawTorso(
    Canvas canvas,
    Offset leftShoulder,
    Offset rightShoulder,
    Offset leftHip,
    Offset rightHip,
  ) {
    final Path torso = Path()
      ..moveTo(leftShoulder.dx, leftShoulder.dy)
      ..quadraticBezierTo(
        (leftShoulder.dx + leftHip.dx) / 2 - 8,
        (leftShoulder.dy + leftHip.dy) / 2,
        leftHip.dx,
        leftHip.dy,
      )
      ..lineTo(rightHip.dx, rightHip.dy)
      ..quadraticBezierTo(
        (rightShoulder.dx + rightHip.dx) / 2 + 8,
        (rightShoulder.dy + rightHip.dy) / 2,
        rightShoulder.dx,
        rightShoulder.dy,
      )
      ..close();

    final Paint torsoFill = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    final Paint torsoShadow = Paint()
      ..color = const Color(0xFFBAE6FD).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    canvas.drawShadow(torso, Colors.black.withValues(alpha: 0.18), 8, false);
    canvas.drawPath(torso, torsoFill);

    final Path highlight = Path()
      ..moveTo(leftShoulder.dx + 4, leftShoulder.dy + 8)
      ..quadraticBezierTo(
        (leftShoulder.dx + leftHip.dx) / 2,
        (leftShoulder.dy + leftHip.dy) / 2 + 4,
        leftHip.dx + 6,
        leftHip.dy - 6,
      )
      ..lineTo(rightHip.dx - 10, rightHip.dy - 2)
      ..quadraticBezierTo(
        rightShoulder.dx - 18,
        (rightShoulder.dy + rightHip.dy) / 2,
        rightShoulder.dx - 6,
        rightShoulder.dy + 10,
      )
      ..close();
    canvas.drawPath(highlight, torsoShadow);
  }

  void _drawStyledLimb(
    Canvas canvas,
    Offset a,
    Offset b,
    Offset c, {
    required double width,
  }) {
    final Paint shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = width + 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint main = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint accent = Paint()
      ..color = const Color(0xFFDBEAFE).withValues(alpha: 0.75)
      ..strokeWidth = width * 0.42
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(a.translate(0, 2), b.translate(0, 2), shadow);
    canvas.drawLine(b.translate(0, 2), c.translate(0, 2), shadow);
    canvas.drawLine(a, b, main);
    canvas.drawLine(b, c, main);
    canvas.drawLine(a, b, accent);
    canvas.drawLine(b, c, accent);
  }

  void _drawHead(Canvas canvas, Offset center, double radius) {
    final Paint head = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    final Paint face = Paint()
      ..color = const Color(0xFFDBEAFE).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center.translate(0, 2),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.14),
    );
    canvas.drawCircle(center, radius, head);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(radius * 0.12, radius * 0.08),
        width: radius * 1.35,
        height: radius * 1.05,
      ),
      face,
    );
  }

  void _drawJoint(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center.translate(0, 1),
      6.2,
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawCircle(center, 5.5, Paint()..color = const Color(0xFFE0F2FE));
  }

  void _drawHand(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 4.6, Paint()..color = const Color(0xFFF8FAFC));
  }

  void _drawFoot(Canvas canvas, Offset center, {required bool left}) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(left ? -0.12 : 0.12);
    final RRect shoe = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, 0), width: 20, height: 9),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      shoe.shift(const Offset(0, 1.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawRRect(shoe, Paint()..color = const Color(0xFFF8FAFC));
    canvas.restore();
  }

  void _drawDumbbell(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final Paint shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint plate = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;
    final Paint plateStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawLine(const Offset(-11, 1.5), const Offset(11, 1.5), shadow);
    canvas.drawLine(const Offset(-11, 0), const Offset(11, 0), handle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-18, 0), width: 8, height: 20),
        const Radius.circular(3),
      ),
      plate,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-18, 0), width: 8, height: 20),
        const Radius.circular(3),
      ),
      plateStroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(18, 0), width: 8, height: 20),
        const Radius.circular(3),
      ),
      plate,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(18, 0), width: 8, height: 20),
        const Radius.circular(3),
      ),
      plateStroke,
    );
    canvas.restore();
  }

  void _drawWeights(
    Canvas canvas, {
    required Offset leftHand,
    required Offset rightHand,
    required double leftGripAngle,
    required double rightGripAngle,
  }) {
    switch (pose) {
      case ExercisePose.singleArmDumbbellRow:
        _drawDumbbell(canvas, leftHand, leftGripAngle);
        break;
      case ExercisePose.dumbbellTricepsExtension:
      case ExercisePose.dumbbellCrunch:
        final Offset center = Offset.lerp(leftHand, rightHand, 0.5)!;
        final double angle = (leftGripAngle + rightGripAngle) / 2;
        _drawDumbbell(canvas, center, angle);
        break;
      case ExercisePose.dumbbellBenchPress:
      case ExercisePose.dumbbellShoulderPress:
      case ExercisePose.dumbbellSquat:
      case ExercisePose.dumbbellRomanianDeadlift:
        _drawDumbbell(canvas, leftHand, leftGripAngle);
        _drawDumbbell(canvas, rightHand, rightGripAngle);
        break;
      case ExercisePose.dumbbellBicepsCurl:
        _drawDumbbell(canvas, leftHand, leftGripAngle);
        break;
    }
  }

  _ResolvedLimb _resolveGuidedLimb(
    Offset start,
    Offset jointGuide,
    Offset endGuide,
    double upperLength,
    double lowerLength,
  ) {
    final Offset jointDirection = _normalizedOrFallback(
      jointGuide - start,
      const Offset(0, 1),
    );
    final Offset joint = start + (jointDirection * upperLength);
    final Offset endDirection = _normalizedOrFallback(
      endGuide - jointGuide,
      jointGuide - start,
    );
    final Offset end = joint + (endDirection * lowerLength);
    return _ResolvedLimb(joint: joint, end: end);
  }

  Offset _normalizedOrFallback(Offset vector, Offset fallback) {
    if (vector.distanceSquared > 0.0001) {
      return vector / vector.distance;
    }
    if (fallback.distanceSquared > 0.0001) {
      return fallback / fallback.distance;
    }
    return const Offset(0, 1);
  }

  Offset _solveJoint(
    Offset start,
    Offset end,
    double upperLength,
    double lowerLength,
    Offset guide,
  ) {
    final Offset delta = end - start;
    final double distance = delta.distance;
    if (distance < 0.001) {
      return Offset.lerp(start, guide, 0.5) ?? start;
    }

    final double minReach = (upperLength - lowerLength).abs() + 0.001;
    final double maxReach = upperLength + lowerLength - 0.001;
    final double clampedDistance = distance.clamp(minReach, maxReach);
    final Offset direction = delta / distance;
    final double projection =
        ((upperLength * upperLength) -
            (lowerLength * lowerLength) +
            (clampedDistance * clampedDistance)) /
        (2 * clampedDistance);
    final double jointHeight = sqrt(
      max((upperLength * upperLength) - (projection * projection), 0),
    );
    final Offset base = start + (direction * projection);
    final Offset normal = Offset(-direction.dy, direction.dx);
    final Offset guideVector = guide - start;
    final double cross =
        (direction.dx * guideVector.dy) - (direction.dy * guideVector.dx);
    final double bendSign = cross >= 0 ? 1 : -1;
    return base + (normal * jointHeight * bendSign);
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
            headCenter: point(0.66, 0.41),
            neck: point(0.58, 0.48),
            hip: point(0.39, 0.59),
            leftElbow: point(0.47, 0.44),
            leftHand: point(0.41, 0.33),
            rightElbow: point(0.69, 0.44),
            rightHand: point(0.75, 0.33),
            leftKnee: point(0.22, 0.62),
            leftFoot: point(0.10, 0.72),
            rightKnee: point(0.18, 0.50),
            rightFoot: point(0.06, 0.54),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.66, 0.41),
            neck: point(0.58, 0.48),
            hip: point(0.39, 0.59),
            leftElbow: point(0.51, 0.27),
            leftHand: point(0.50, 0.11),
            rightElbow: point(0.65, 0.27),
            rightHand: point(0.66, 0.11),
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
            headCenter: point(0.64, 0.22),
            neck: point(0.58, 0.31),
            hip: point(0.43, 0.50),
            leftElbow: point(0.53, 0.56),
            leftHand: point(0.53, 0.80),
            rightElbow: point(0.62, 0.40),
            rightHand: point(0.64, 0.50),
            leftKnee: point(0.39, 0.68),
            leftFoot: point(0.31, 0.90),
            rightKnee: point(0.59, 0.66),
            rightFoot: point(0.71, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 10,
          ),
          _PosePoints(
            headCenter: point(0.64, 0.22),
            neck: point(0.58, 0.31),
            hip: point(0.43, 0.50),
            leftElbow: point(0.36, 0.41),
            leftHand: point(0.36, 0.65),
            rightElbow: point(0.62, 0.40),
            rightHand: point(0.64, 0.50),
            leftKnee: point(0.39, 0.68),
            leftFoot: point(0.31, 0.90),
            rightKnee: point(0.59, 0.66),
            rightFoot: point(0.71, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 10,
          ),
        );
      case ExercisePose.dumbbellShoulderPress:
        return (
          _PosePoints(
            headCenter: point(0.50, 0.16),
            neck: point(0.50, 0.28),
            hip: point(0.50, 0.53),
            leftElbow: point(0.39, 0.36),
            leftHand: point(0.33, 0.27),
            rightElbow: point(0.61, 0.36),
            rightHand: point(0.67, 0.27),
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
            leftElbow: point(0.44, 0.20),
            leftHand: point(0.39, 0.06),
            rightElbow: point(0.56, 0.20),
            rightHand: point(0.61, 0.06),
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
            leftElbow: point(0.44, 0.48),
            leftHand: point(0.34, 0.62),
            rightElbow: point(0.58, 0.50),
            rightHand: point(0.60, 0.74),
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
            leftElbow: point(0.44, 0.48),
            leftHand: point(0.50, 0.34),
            rightElbow: point(0.58, 0.50),
            rightHand: point(0.60, 0.74),
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
            leftElbow: point(0.42, 0.28),
            leftHand: point(0.47, 0.23),
            rightElbow: point(0.58, 0.28),
            rightHand: point(0.53, 0.23),
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
            leftElbow: point(0.45, 0.18),
            leftHand: point(0.48, 0.05),
            rightElbow: point(0.55, 0.18),
            rightHand: point(0.52, 0.05),
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
            hip: point(0.50, 0.50),
            leftElbow: point(0.40, 0.47),
            leftHand: point(0.36, 0.63),
            rightElbow: point(0.60, 0.47),
            rightHand: point(0.64, 0.63),
            leftKnee: point(0.41, 0.66),
            leftFoot: point(0.41, 0.90),
            rightKnee: point(0.59, 0.66),
            rightFoot: point(0.59, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.50, 0.21),
            neck: point(0.50, 0.34),
            hip: point(0.50, 0.65),
            leftElbow: point(0.41, 0.52),
            leftHand: point(0.35, 0.70),
            rightElbow: point(0.59, 0.52),
            rightHand: point(0.65, 0.70),
            leftKnee: point(0.39, 0.68),
            leftFoot: point(0.39, 0.90),
            rightKnee: point(0.61, 0.68),
            rightFoot: point(0.61, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellRomanianDeadlift:
        return (
          _PosePoints(
            headCenter: point(0.52, 0.17),
            neck: point(0.50, 0.29),
            hip: point(0.50, 0.51),
            leftElbow: point(0.43, 0.46),
            leftHand: point(0.41, 0.62),
            rightElbow: point(0.57, 0.46),
            rightHand: point(0.59, 0.62),
            leftKnee: point(0.42, 0.70),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.70),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
          _PosePoints(
            headCenter: point(0.58, 0.23),
            neck: point(0.54, 0.33),
            hip: point(0.46, 0.56),
            leftElbow: point(0.44, 0.56),
            leftHand: point(0.41, 0.79),
            rightElbow: point(0.54, 0.56),
            rightHand: point(0.59, 0.79),
            leftKnee: point(0.42, 0.75),
            leftFoot: point(0.36, 0.90),
            rightKnee: point(0.58, 0.75),
            rightFoot: point(0.64, 0.90),
            leftGripAngle: pi / 2,
            rightGripAngle: pi / 2,
          ),
        );
      case ExercisePose.dumbbellCrunch:
        return (
          _PosePoints(
            headCenter: point(0.60, 0.52),
            neck: point(0.55, 0.58),
            hip: point(0.40, 0.66),
            leftElbow: point(0.56, 0.48),
            leftHand: point(0.61, 0.44),
            rightElbow: point(0.51, 0.56),
            rightHand: point(0.56, 0.50),
            leftKnee: point(0.26, 0.70),
            leftFoot: point(0.18, 0.88),
            rightKnee: point(0.28, 0.58),
            rightFoot: point(0.16, 0.73),
            leftGripAngle: pi / 8,
            rightGripAngle: pi / 8,
          ),
          _PosePoints(
            headCenter: point(0.69, 0.39),
            neck: point(0.62, 0.47),
            hip: point(0.40, 0.62),
            leftElbow: point(0.63, 0.35),
            leftHand: point(0.67, 0.29),
            rightElbow: point(0.58, 0.44),
            rightHand: point(0.63, 0.38),
            leftKnee: point(0.26, 0.70),
            leftFoot: point(0.18, 0.88),
            rightKnee: point(0.28, 0.58),
            rightFoot: point(0.16, 0.73),
            leftGripAngle: pi / 8,
            rightGripAngle: pi / 8,
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

class _ResolvedLimb {
  const _ResolvedLimb({required this.joint, required this.end});

  final Offset joint;
  final Offset end;
}
