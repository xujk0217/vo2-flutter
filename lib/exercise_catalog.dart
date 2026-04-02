import 'dart:math';

import 'package:flutter/material.dart';

enum ExercisePose {
  jumpingJack,
  squat,
  lunge,
  pushUp,
  sitUp,
  highKnees,
  burpee,
  mountainClimber,
}

class ExerciseType {
  const ExerciseType({
    required this.label,
    required this.caption,
    required this.pose,
    required this.startColor,
    required this.endColor,
    required this.icon,
  });

  final String label;
  final String caption;
  final ExercisePose pose;
  final Color startColor;
  final Color endColor;
  final IconData icon;
}

const List<ExerciseType> exerciseCatalog = <ExerciseType>[
  ExerciseType(
    label: '開合跳',
    caption: '全身暖身',
    pose: ExercisePose.jumpingJack,
    startColor: Color(0xFF1D4ED8),
    endColor: Color(0xFF38BDF8),
    icon: Icons.accessibility_new_rounded,
  ),
  ExerciseType(
    label: '深蹲',
    caption: '下肢力量',
    pose: ExercisePose.squat,
    startColor: Color(0xFF0F766E),
    endColor: Color(0xFF2DD4BF),
    icon: Icons.fitness_center_rounded,
  ),
  ExerciseType(
    label: '弓步蹲',
    caption: '腿臀穩定',
    pose: ExercisePose.lunge,
    startColor: Color(0xFF9333EA),
    endColor: Color(0xFFC084FC),
    icon: Icons.directions_walk_rounded,
  ),
  ExerciseType(
    label: '伏地挺身',
    caption: '上肢推力',
    pose: ExercisePose.pushUp,
    startColor: Color(0xFFB45309),
    endColor: Color(0xFFF59E0B),
    icon: Icons.front_hand_rounded,
  ),
  ExerciseType(
    label: '仰臥起坐',
    caption: '核心訓練',
    pose: ExercisePose.sitUp,
    startColor: Color(0xFFBE123C),
    endColor: Color(0xFFFB7185),
    icon: Icons.self_improvement_rounded,
  ),
  ExerciseType(
    label: '高抬腿',
    caption: '心肺刺激',
    pose: ExercisePose.highKnees,
    startColor: Color(0xFF047857),
    endColor: Color(0xFF4ADE80),
    icon: Icons.directions_run_rounded,
  ),
  ExerciseType(
    label: '波比跳',
    caption: '爆發訓練',
    pose: ExercisePose.burpee,
    startColor: Color(0xFFC2410C),
    endColor: Color(0xFFFB923C),
    icon: Icons.bolt_rounded,
  ),
  ExerciseType(
    label: '登山者',
    caption: '核心節奏',
    pose: ExercisePose.mountainClimber,
    startColor: Color(0xFF1F2937),
    endColor: Color(0xFF60A5FA),
    icon: Icons.terrain_rounded,
  ),
];

ExerciseType randomExercise([Random? random]) {
  final Random generator = random ?? Random();
  return exerciseCatalog[generator.nextInt(exerciseCatalog.length)];
}
