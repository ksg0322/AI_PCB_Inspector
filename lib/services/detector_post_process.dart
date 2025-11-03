import 'dart:typed_data';
import '../models/pcb_defect_models.dart';
import '../utils/detector_utils.dart';

/// 후처리 설정
class PostProcessConfig {
  final double confidenceThreshold;
  final double nmsThreshold;
  final bool agnosticNms;
  final int maxDetections;
  final List<String> classLabels;

  const PostProcessConfig({
    this.confidenceThreshold = 0.15,
    this.nmsThreshold = 0.5,
    this.agnosticNms = false,
    this.maxDetections = 50,
    required this.classLabels,
  });
}

/// 모델 출력 후처리 함수
List<DetectedDefect> postprocessOutputAdvanced(
  Float32List output,
  int originalWidth,
  int originalHeight,
  List<int> outputShape,
  bool needsTranspose,
  bool hasObjectness,
  List<String> classLabels, {
  double scale = 1.0,
  double padX = 0.0,
  double padY = 0.0,
  double minConfidence = 0.15,
  double nmsThreshold = 0.5,
  bool agnosticNms = false,
  int maxDetections = 50,
}) {
  final detections = <DetectedDefect>[];

  try {
    // 모델 출력 처리
    List<List<double>> processedOutput;
    if (needsTranspose) {
      processedOutput = transposeOutput(output, outputShape);
    } else {
      processedOutput = directReshape(output, outputShape);
    }

    // 각 탐지 결과 처리
    for (int i = 0; i < processedOutput.length; i++) {
      final detection = processedOutput[i];

      if (detection.length < 5) continue;

      // YOLOv11n-seg 헤드 해석: [cx, cy, w, h, cls0, cls1, cls2, cls3, mask_coeffs...]
      final objIndex = 4;
      final classStart = hasObjectness ? 5 : 4; // objectness 유무에 따라 조정
      final objectness = hasObjectness ? detection[objIndex] : 1.0;

      // objectness가 로짓 형태일 수 있으므로 sigmoid 적용
      final objScore = (objectness < 0.0 || objectness > 1.0)
          ? sigmoid(objectness)
          : objectness;

      if (objScore < minConfidence) continue;

      double maxClassConfidence = 0.0;
      int bestClassIndex = -1;

      for (int classIndex = 0; classIndex < classLabels.length; classIndex++) {
        final classIdx = classStart + classIndex;
        if (classIdx >= detection.length) break; // 배열 범위 체크

        double classConfidence = detection[classIdx];
        // 클래스 확률도 로짓일 수 있으므로 sigmoid 적용
        if (classConfidence < 0.0 || classConfidence > 1.0) {
          classConfidence = sigmoid(classConfidence);
        }
        if (classConfidence > maxClassConfidence) {
          maxClassConfidence = classConfidence;
          bestClassIndex = classIndex;
        }
      }

      // 최종 신뢰도 = objectness * max(class_probability)
      final finalConfidence = objScore * maxClassConfidence;

      // 최종 신뢰도 임계값 확인
      if (finalConfidence >= minConfidence && bestClassIndex != -1) {
        // 바운딩 박스 좌표 변환 (YOLO 출력 → 픽셀 좌표)
        // YOLO 출력: [center_x, center_y, width, height] (일부 모델은 0~1 정규화, 일부는 입력 해상도 픽셀)
        double cx = detection[0];
        double cy = detection[1];
        double bw = detection[2];
        double bh = detection[3];

        // 모델 입력 공간(패딩 포함 640x640)으로 좌표 통일
        const int inputDim = 640;
        final bool isNormalized =
            (cx <= 1.5 && cy <= 1.5 && bw <= 1.5 && bh <= 1.5);
        final double cxPadded = isNormalized ? cx * inputDim : cx;
        final double cyPadded = isNormalized ? cy * inputDim : cy;
        final double bwPadded = isNormalized ? bw * inputDim : bw;
        final double bhPadded = isNormalized ? bh * inputDim : bh;

        // 패딩 제거 및 원본 이미지 좌표계로 복원
        final double centerXOriginal = (cxPadded - padX) / scale;
        final double centerYOriginal = (cyPadded - padY) / scale;
        final double boxWidthOriginal = bwPadded / scale;
        final double boxHeightOriginal = bhPadded / scale;

        final left = centerXOriginal - boxWidthOriginal / 2;
        final top = centerYOriginal - boxHeightOriginal / 2;
        final width = boxWidthOriginal;
        final height = boxHeightOriginal;

        // 좌표 유효성 검사
        if (left < 0 ||
            top < 0 ||
            width <= 0 ||
            height <= 0 ||
            left + width > originalWidth ||
            top + height > originalHeight) {
          continue;
        }

        // 박스 크기 유효성 검사
        final minBoxSize = 10.0;
        final maxBoxSize =
            (originalWidth < originalHeight ? originalWidth : originalHeight) *
            0.8;
        if (width < minBoxSize ||
            height < minBoxSize ||
            width > maxBoxSize ||
            height > maxBoxSize) {
          continue;
        }

        // 좌표 정규화 및 클램핑
        final bbox = RectLike(
          left: left.clamp(0.0, originalWidth.toDouble()),
          top: top.clamp(0.0, originalHeight.toDouble()),
          width: width.clamp(0.0, originalWidth.toDouble()),
          height: height.clamp(0.0, originalHeight.toDouble()),
        );

        detections.add(
          DetectedDefect(
            label: classLabels[bestClassIndex],
            confidence: finalConfidence,
            bbox: bbox,
            sourceWidth: originalWidth,
            sourceHeight: originalHeight,
            detectedAt: DateTime.now(), // 탐지 시간 추가
          ),
        );
      }
    }

    // NMS 적용
    final filteredDetections = applyAdvancedNMS(
      detections,
      nmsThreshold,
      agnosticNms,
      maxDetections,
    );

    // 탐지가 전혀 없으면 임계값을 자동으로 완화하여 재시도
    if (filteredDetections.isEmpty && minConfidence > 0.10) {
      return postprocessOutputAdvanced(
        output,
        originalWidth,
        originalHeight,
        outputShape,
        needsTranspose,
        hasObjectness,
        classLabels,
        scale: scale,
        padX: padX,
        padY: padY,
        minConfidence: 0.10,
        nmsThreshold: nmsThreshold,
        agnosticNms: agnosticNms,
        maxDetections: maxDetections,
      );
    }

    return filteredDetections;
  } catch (e) {
    print('❌ 후처리 오류: $e');
    return <DetectedDefect>[];
  }
}

/// NMS(Non-Maximum Suppression) 적용 함수
List<DetectedDefect> applyAdvancedNMS(
  List<DetectedDefect> detections,
  double nmsThreshold,
  bool agnosticNms,
  int maxDetections,
) {
  if (detections.isEmpty) return detections;

  // 신뢰도 순으로 정렬
  detections.sort((a, b) => b.confidence.compareTo(a.confidence));

  final keep = <DetectedDefect>[];
  final suppressed = List<bool>.filled(detections.length, false);

  for (int i = 0; i < detections.length; i++) {
    if (suppressed[i]) continue;

    // 최대 탐지 수 제한
    if (keep.length >= maxDetections) break;
    keep.add(detections[i]);

    for (int j = i + 1; j < detections.length; j++) {
      if (suppressed[j]) continue;

      // 같은 클래스인지 확인 (class-agnostic가 아니면 클래스 일치 필요)
      if (!agnosticNms && detections[i].label != detections[j].label) continue;

      // IoU 계산
      final iou = calculateIoU(detections[i].bbox, detections[j].bbox);
      if (iou > nmsThreshold) {
        suppressed[j] = true;
      }
    }
  }

  return keep;
}
