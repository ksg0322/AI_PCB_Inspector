import '../models/pcb_defect_models.dart';

class DefectSummaryUtil {
  static String generateDescription(List<DetectedDefect> defects) {
    if (defects.isEmpty) return '결함이 탐지되지 않았습니다.';

    final counts = <String, int>{};
    for (final defect in defects) {
      counts[defect.label] = (counts[defect.label] ?? 0) + 1;
    }

    final descriptions = counts.entries
        .map((e) => '${e.key} ${e.value}건')
        .join(', ');
    return '총 ${defects.length}건의 결함: $descriptions';
  }
}


