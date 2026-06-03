import 'dart:math';

import 'package:flutter/material.dart';

enum ExercisePose {
  dumbbellBenchPress,
  singleArmDumbbellRow,
  dumbbellShoulderPress,
  dumbbellBicepsCurl,
  dumbbellTricepsExtension,
  dumbbellSquat,
  dumbbellRomanianDeadlift,
  dumbbellCrunch,
}

enum MuscleGroup {
  chest('胸肌'),
  back('背肌'),
  shoulders('肩部'),
  biceps('二頭肌'),
  triceps('三頭肌'),
  core('核心'),
  quads('股四頭肌'),
  glutes('臀部'),
  hamstrings('腿後側');

  const MuscleGroup(this.label);

  final String label;
}

class ExerciseType {
  const ExerciseType({
    required this.label,
    required this.caption,
    required this.pose,
    required this.startColor,
    required this.endColor,
    required this.icon,
    required this.muscleGroups,
  });

  final String label;
  final String caption;
  final ExercisePose pose;
  final Color startColor;
  final Color endColor;
  final IconData icon;
  final List<MuscleGroup> muscleGroups;
}

const List<ExerciseType> exerciseCatalog = <ExerciseType>[
  ExerciseType(
    label: '啞鈴臥推',
    caption: '胸推訓練',
    pose: ExercisePose.dumbbellBenchPress,
    startColor: Color(0xFF1D4ED8),
    endColor: Color(0xFF60A5FA),
    icon: Icons.fitness_center_rounded,
    muscleGroups: <MuscleGroup>[
      MuscleGroup.chest,
      MuscleGroup.shoulders,
      MuscleGroup.triceps,
    ],
  ),
  ExerciseType(
    label: '單手啞鈴划船',
    caption: '背部拉力',
    pose: ExercisePose.singleArmDumbbellRow,
    startColor: Color(0xFF0F766E),
    endColor: Color(0xFF2DD4BF),
    icon: Icons.fitness_center_rounded,
    muscleGroups: <MuscleGroup>[
      MuscleGroup.back,
      MuscleGroup.biceps,
      MuscleGroup.core,
    ],
  ),
  ExerciseType(
    label: '啞鈴肩推',
    caption: '肩部推舉',
    pose: ExercisePose.dumbbellShoulderPress,
    startColor: Color(0xFF9333EA),
    endColor: Color(0xFFC084FC),
    icon: Icons.front_hand_rounded,
    muscleGroups: <MuscleGroup>[
      MuscleGroup.shoulders,
      MuscleGroup.triceps,
      MuscleGroup.core,
    ],
  ),
  ExerciseType(
    label: '啞鈴二頭彎舉',
    caption: '手臂屈曲',
    pose: ExercisePose.dumbbellBicepsCurl,
    startColor: Color(0xFFB45309),
    endColor: Color(0xFFF59E0B),
    icon: Icons.sports_gymnastics_rounded,
    muscleGroups: <MuscleGroup>[MuscleGroup.biceps, MuscleGroup.shoulders],
  ),
  ExerciseType(
    label: '啞鈴三頭彎舉',
    caption: '三頭伸展',
    pose: ExercisePose.dumbbellTricepsExtension,
    startColor: Color(0xFFBE123C),
    endColor: Color(0xFFFB7185),
    icon: Icons.fitness_center_rounded,
    muscleGroups: <MuscleGroup>[MuscleGroup.triceps, MuscleGroup.shoulders],
  ),
  ExerciseType(
    label: '啞鈴深蹲',
    caption: '下肢力量',
    pose: ExercisePose.dumbbellSquat,
    startColor: Color(0xFF047857),
    endColor: Color(0xFF4ADE80),
    icon: Icons.accessibility_new_rounded,
    muscleGroups: <MuscleGroup>[
      MuscleGroup.quads,
      MuscleGroup.glutes,
      MuscleGroup.core,
    ],
  ),
  ExerciseType(
    label: '啞鈴羅馬尼亞硬舉',
    caption: '臀腿後鏈',
    pose: ExercisePose.dumbbellRomanianDeadlift,
    startColor: Color(0xFFC2410C),
    endColor: Color(0xFFFB923C),
    icon: Icons.straighten_rounded,
    muscleGroups: <MuscleGroup>[
      MuscleGroup.hamstrings,
      MuscleGroup.glutes,
      MuscleGroup.back,
    ],
  ),
  ExerciseType(
    label: '啞鈴負重卷腹',
    caption: '核心捲腹',
    pose: ExercisePose.dumbbellCrunch,
    startColor: Color(0xFF1F2937),
    endColor: Color(0xFF60A5FA),
    icon: Icons.self_improvement_rounded,
    muscleGroups: <MuscleGroup>[MuscleGroup.core],
  ),
];

ExerciseType randomExercise([Random? random]) {
  final Random generator = random ?? Random();
  return exerciseCatalog[generator.nextInt(exerciseCatalog.length)];
}
