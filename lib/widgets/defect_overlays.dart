import 'package:flutter/material.dart';
import '../models/pcb_defect_models.dart';
import '../utils/defect_overlay_util.dart';

class DefectOverlays extends StatelessWidget {
  final List<DetectedDefect> defects;
  final double offsetX;
  final double offsetY;
  final double actualImageWidth;
  final double actualImageHeight;

  const DefectOverlays({
    super.key,
    required this.defects,
    required this.offsetX,
    required this.offsetY,
    required this.actualImageWidth,
    required this.actualImageHeight,
  });

  Color _colorFor(String label) => DefectOverlayUtil.getFlutterColor(label);

  @override
  Widget build(BuildContext context) {
    if (defects.isEmpty) return const SizedBox.shrink();

    // 모든 결함 표시 (신뢰도 필터링 제거)
    final Map<String, int> counters = {};
    final List<Widget> children = [];

    for (final defect in defects) {
      counters[defect.label] = (counters[defect.label] ?? 0) + 1;
      final defectNumber = counters[defect.label]!;

      // 모든 모드에서 동일한 좌표 변환 (CameraPreview 기반 탐지로 통일)
      final double baseW = defect.sourceWidth.toDouble();
      final double baseH = defect.sourceHeight.toDouble();

      // 탐지 결과 좌표를 그대로 사용 (CameraPreview와 동일한 해상도)
      final double transformedLeft = defect.bbox.left;
      final double transformedTop = defect.bbox.top;
      final double transformedWidth = defect.bbox.width;
      final double transformedHeight = defect.bbox.height;

      // 최종 화면 좌표로 변환
      final double left =
          offsetX + (transformedLeft / baseW) * actualImageWidth;
      final double top = offsetY + (transformedTop / baseH) * actualImageHeight;
      final double w = (transformedWidth / baseW) * actualImageWidth;
      final double h = (transformedHeight / baseH) * actualImageHeight;

      final pos = DefectOverlayUtil.getLabelPosition(
        defect.label,
        RectLike(left: left, top: top, width: w, height: h),
      );
      final numberLeft = pos.left;
      final numberTop = pos.top;

      children.add(
        Positioned(
          left: left,
          top: top,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              border: Border.all(color: _colorFor(defect.label), width: 2),
            ),
          ),
        ),
      );

      children.add(
        Positioned(
          left: numberLeft,
          top: numberTop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _colorFor(defect.label),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$defectNumber',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(children: children);
  }
}
