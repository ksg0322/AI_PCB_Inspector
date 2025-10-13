import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

/// PCB 결함 탐지 모델 설정 및 초기화 (YOLOv11n-seg 전이학습 모델)
class PCBDefectModelConfig {
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.15;
  static const double nmsThreshold = 0.5;
  static const bool agnosticNms = false;
  static const int maxDetections = 50;
  static const String modelPath =
      'assets/best_float16.tflite'; // YOLOv11n-seg 전이학습 모델
  static const bool enableGpu = true; // GPU Delegate 사용 여부

  /// 탐지 가능한 결함 클래스 라벨들 (YOLOv11n-seg 전이학습 모델)
  static const List<String> classLabels = [
    'Dry_joint',
    'Incorrect_installation',
    'PCB_damage',
    'Short_circuit',
  ];

  /// 결함 클래스별 색상 매핑
  static const Map<String, int> defectColors = {
    'Dry_joint': 0xFFFF9800, // Orange
    'Incorrect_installation': 0xFF2196F3, // Blue
    'PCB_damage': 0xFF9C27B0, // Purple
    'Short_circuit': 0xFFF44336, // Red
  };

  /// 모델 초기화
  static Future<Interpreter> initializeModel() async {
    final gpuTried = enableGpu && Platform.isAndroid;
    // 1) 1차: GPU 시도 (Android)
    try {
      final options = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = false; // GPU와 동시 사용 금지

      if (gpuTried) {
        try {
          final gpu = GpuDelegateV2();
          options.addDelegate(gpu);
          print('✅ Android GPU Delegate 활성화');
        } catch (e) {
          print('⚠️ GPU Delegate 추가 실패, CPU로 폴백 예정: $e');
        }
      }

      final interpreter = await Interpreter.fromAsset(
        modelPath,
        options: options,
      );
      print('✅ YOLOv11n-seg PCB 결함 탐지 모델 초기화 완료 (GPU시도=${gpuTried})');
      return interpreter;
    } catch (e) {
      print('⚠️ 1차 초기화 실패 (GPU 시도 포함 가능): $e');
      // 2) 2차: CPU 폴백 (XNNPACK)
      try {
        final cpuOptions = InterpreterOptions()
          ..threads = 4
          ..useNnApiForAndroid = false; // XNNPACK 경로 유지
        final interpreter = await Interpreter.fromAsset(
          modelPath,
          options: cpuOptions,
        );
        print('✅ YOLOv11n-seg CPU 폴백으로 모델 초기화 성공');
        return interpreter;
      } catch (e2) {
        print('❌ 모델 로딩 실패(폴백 포함): $e2');
        rethrow;
      }
    }
  }

  /// 모델 검증 및 설정 정보 반환
  static ModelConfig validateAndConfigureModel(Interpreter interpreter) {
    try {
      // 모델 입력/출력 정보 확인
      final inputTensor = interpreter.getInputTensor(0);
      final outputTensor = interpreter.getOutputTensor(0);
      final inputShape = inputTensor.shape;
      final outputShape = outputTensor.shape;

      // 모델 호환성 검사
      if (inputShape.length != 4 ||
          inputShape[1] != inputSize ||
          inputShape[2] != inputSize ||
          inputShape[3] != 3) {
        print('⚠️ 입력 형식이 예상과 다름: $inputShape');
      }

      bool needsTranspose = false;
      bool hasObjectness = true;
      int numDetections = 8400;
      int numClasses = classLabels.length;

      if (outputShape.length == 3 && outputShape[1] < outputShape[2]) {
        // [1, 40, 8400] 형태 - transpose 필요
        needsTranspose = true;
        numDetections = outputShape[2];
        final features = outputShape[1];
        final remaining = features - 4 - numClasses;

        if (remaining == 32) {
          // YOLOv11n-seg: 4(box) + 4(classes) + 32(masks) = 40 (objectness 없음)
          hasObjectness = false;
        } else if (remaining == 33) {
          // YOLOv11n-seg: 4(box) + 1(obj) + 4(classes) + 32(masks) = 41 (objectness 있음)
          hasObjectness = true;
        } else {
          // YOLOv11n-seg 기본값 (objectness 있음)
          hasObjectness = true;
        }
      } else if (outputShape.length == 3) {
        // [1, 8400, 40] 형태 - transpose 불필요
        needsTranspose = false;
        numDetections = outputShape[1];
        final features = outputShape[2];
        final remaining = features - 4 - numClasses;

        if (remaining == 32) {
          // YOLOv11n-seg: 4(box) + 4(classes) + 32(masks) = 40 (objectness 없음)
          hasObjectness = false;
        } else if (remaining == 33) {
          // YOLOv11n-seg: 4(box) + 1(obj) + 4(classes) + 32(masks) = 41 (objectness 있음)
          hasObjectness = true;
        } else {
          // YOLOv11n-seg 기본값 (objectness 있음)
          hasObjectness = true;
        }
      } else {
        // YOLOv11n-seg 기본 설정
        numDetections = 8400;
        needsTranspose = true;
      }

      return ModelConfig(
        needsTranspose: needsTranspose,
        hasObjectness: hasObjectness,
        numDetections: numDetections,
        numClasses: numClasses,
        inputShape: inputShape,
        outputShape: outputShape,
      );
    } catch (e) {
      print('❌ 모델 검증 실패: $e');
      // YOLOv11n-seg 기본값으로 대체
      return ModelConfig(
        needsTranspose: true,
        hasObjectness: true,
        numDetections: 8400,
        numClasses: classLabels.length,
        inputShape: [1, inputSize, inputSize, 3],
        outputShape: [
          1,
          41,
          8400,
        ], // YOLOv11n-seg: 4(box) + 1(obj) + 4(classes) + 32(masks)
      );
    }
  }
}

/// 모델 설정 정보 클래스
class ModelConfig {
  final bool needsTranspose;
  final bool hasObjectness;
  final int numDetections;
  final int numClasses;
  final List<int> inputShape;
  final List<int> outputShape;

  const ModelConfig({
    required this.needsTranspose,
    required this.hasObjectness,
    required this.numDetections,
    required this.numClasses,
    required this.inputShape,
    required this.outputShape,
  });

  @override
  String toString() {
    return 'ModelConfig(needsTranspose: $needsTranspose, hasObjectness: $hasObjectness, '
        'numDetections: $numDetections, numClasses: $numClasses)';
  }
}

/// 바운딩 박스 관련 클래스
class RectLike {
  final double left;
  final double top;
  final double width;
  final double height;

  const RectLike({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() {
    return 'RectLike(left: $left, top: $top, width: $width, height: $height)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RectLike &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return left.hashCode ^ top.hashCode ^ width.hashCode ^ height.hashCode;
  }
}

/// 탐지된 PCB 결함 정보 클래스
class DetectedDefect {
  final String label;
  final double confidence;
  final RectLike bbox;
  final int sourceWidth;
  final int sourceHeight;
  final DateTime detectedAt; // 탐지 시간
  final Duration displayDuration; // 표시 지속 시간

  const DetectedDefect({
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.detectedAt,
    this.displayDuration = const Duration(milliseconds: 600),
  });

  @override
  String toString() {
    return 'DetectedDefect(label: $label, confidence: ${(confidence * 100).toStringAsFixed(1)}%, bbox: $bbox)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectedDefect &&
        other.label == label &&
        other.confidence == confidence &&
        other.bbox == bbox &&
        other.sourceWidth == sourceWidth &&
        other.sourceHeight == sourceHeight;
  }

  @override
  int get hashCode {
    return label.hashCode ^
        confidence.hashCode ^
        bbox.hashCode ^
        sourceWidth.hashCode ^
        sourceHeight.hashCode ^
        detectedAt.hashCode;
  }

  /// 신뢰도를 퍼센트로 반환
  int get confidencePercent => (confidence * 100).round();

  /// 바운딩 박스의 중심점 반환
  Point<double> get center =>
      Point<double>(bbox.left + bbox.width / 2, bbox.top + bbox.height / 2);

  /// 바운딩 박스의 면적 반환
  double get area => bbox.width * bbox.height;

  /// 박스가 아직 유효한지 확인 (만료 시간 체크)
  bool get isValid => DateTime.now().isBefore(detectedAt.add(displayDuration));

  /// 남은 표시 시간 (밀리초)
  int get remainingTimeMs =>
      detectedAt.add(displayDuration).difference(DateTime.now()).inMilliseconds;
}

/// 2D 점 클래스
class Point<T extends num> {
  final T x;
  final T y;

  const Point(this.x, this.y);

  @override
  String toString() => 'Point($x, $y)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Point<T> && other.x == x && other.y == y;
  }

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}
