import 'package:flutter/material.dart';
import '../models/pcb_defect_models.dart';

class DefectOverlayUtil {
  /// 결함 라벨에 대한 Flutter Color 반환 (중앙 색상 매핑 사용)
  static Color getFlutterColor(String label) {
    final colorInt = PCBDefectModelConfig.defectColors[label];
    if (colorInt == null) {
      return Colors.grey;
    }
    return Color(colorInt);
  }

  /// 결함 라벨에 대한 ARGB 정수 반환 (없으면 null)
  static int? getColorInt(String label) {
    return PCBDefectModelConfig.defectColors[label];
  }

  /// 결함 라벨의 RGB 채널 값을 반환 (fallback: 회색)
  static ({int r, int g, int b}) getRgb(String label) {
    final colorInt = PCBDefectModelConfig.defectColors[label];
    if (colorInt == null) {
      return (r: 128, g: 128, b: 128);
    }
    final r = (colorInt >> 16) & 0xFF;
    final g = (colorInt >> 8) & 0xFF;
    final b = colorInt & 0xFF;
    return (r: r, g: g, b: b);
  }

  /// 앱과 동일한 라벨 위치 계산
  static ({double left, double top}) getLabelPosition(
    String label,
    RectLike bbox,
  ) {
    double left = bbox.left;
    double top = bbox.top;
    switch (label) {
      case 'Dry_joint':
        left = bbox.left - 22;
        top = bbox.top - 3;
        break;
      case 'Short_circuit':
        left = bbox.left + bbox.width + 2;
        top = bbox.top - 3;
        break;
      case 'PCB_damage':
        left = bbox.left - 22;
        top = bbox.top + bbox.height - 15;
        break;
      case 'Incorrect_installation':
        left = bbox.left + bbox.width + 2;
        top = bbox.top + bbox.height - 15;
        break;
      default:
        left = bbox.left - 22;
        top = bbox.top - 3;
    }
    return (left: left, top: top);
  }
}
