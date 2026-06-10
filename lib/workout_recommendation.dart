import 'package:vo2_flutter/models/workout_models.dart';

class WorkoutRecommendation {
  const WorkoutRecommendation({
    required this.headline,
    required this.coachingText,
    required this.nextWorkoutText,
  });

  final String headline;
  final String coachingText;
  final String nextWorkoutText;
}

class WorkoutRecommendationBuilder {
  const WorkoutRecommendationBuilder();

  WorkoutRecommendation build(WorkoutHistoryEntry entry) {
    final WorkoutRecommendationInput? input = entry.recommendationInput;
    final bool highRpe = input?.hasHighRpeInterval ?? entry.rpeAvg >= 8;
    final bool lowRpe = input?.hasLowRpeInterval ?? entry.rpeAvg <= 4;
    final int trend = input?.vo2Trend ?? 0;
    final int loadStatus = input?.loadStatus ?? entry.loadStatus;

    if (highRpe) {
      return const WorkoutRecommendation(
        headline: '今天強度偏高，恢復會讓下一組更穩。',
        coachingText: '你已經推到接近上限。下一次先把動作品質守住，組間多休 30 到 45 秒，讓呼吸回到可控制節奏。',
        nextWorkoutText: '建議下一練：維持重量，總組數減少一組，專注每一下完整路徑。',
      );
    }

    if (lowRpe && entry.vo2Avg > 0) {
      return const WorkoutRecommendation(
        headline: '身體還有餘裕，可以安全提高刺激。',
        coachingText: '這次主觀強度偏低，心肺反應也穩定。若動作沒有跑掉，下次可以小幅增加重量或每組多 2 下。',
        nextWorkoutText: '建議下一練：同樣動作增加 5% 重量，或每個主動作多做一組。',
      );
    }

    if (trend == 2 || loadStatus == 2) {
      return const WorkoutRecommendation(
        headline: '負荷累積明顯，先把節奏拉回可持續。',
        coachingText: '後段耗氧與疲勞一起上升，代表訓練刺激足夠。下一次不用追更快，先維持穩定呼吸和一致速度。',
        nextWorkoutText: '建議下一練：同重量，延長暖身，主訓練保持 7 成力。',
      );
    }

    return const WorkoutRecommendation(
      headline: '訓練節奏穩定，這是一堂扎實的基準課。',
      coachingText: '你的動作量、VO2 與 RPE 落在可持續區間。保持同樣節奏，逐步累積，比一次衝太高更能提升體能。',
      nextWorkoutText: '建議下一練：維持目前重量，優先把每個動作的有效次數做滿。',
    );
  }
}
