import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../models/pcb_defect_models.dart';
import '../utils/detector_utils.dart';
import 'detector_post_process.dart';

/// PCB 결함 탐지 서비스
class DetectorService {
  Interpreter? _interpreter;
  ModelConfig? _modelConfig;

  // 마지막 탐지 결과 캐시 (프레임 스킵 시 박스 유지용)
  List<DetectedDefect> _lastDetections = const <DetectedDefect>[];

  // 공개 게터: 마지막 탐지 결과 (UI에서 참조용)
  List<DetectedDefect> get lastDetections => _lastDetections;

  // 프레임 스킵을 위한 변수들
  int _frameCounter = 0;
  int _lastProcessedFrame = 0;
  static const int _frameSkipInterval = 8; // 8프레임마다 1번 처리 (더 적극적으로 스킵)
  DateTime? _lastProcessTime;
  static const Duration _minProcessInterval = Duration(
    milliseconds: 800,
  ); // 최소 500ms 간격 (더 긴 간격)

  // 처리 중인지 확인하는 플래그
  bool _isProcessing = false;

  // 탐지 일시 중지 플래그 (촬영 중 등)
  bool _isPaused = false;

  // 동적 스킵을 위한 변수들
  int _consecutiveSkips = 0;
  static const int _maxConsecutiveSkips = 5; // 최대 연속 스킵 수 (더 적극적으로 스킵)

  /// 모델 초기화 (한 번만 실행)
  Future<void> initialize() async {
    if (_interpreter != null) return; // 이미 초기화된 경우 스킵

    try {
      _interpreter = await PCBDefectModelConfig.initializeModel();
      _modelConfig = PCBDefectModelConfig.validateAndConfigureModel(
        _interpreter!,
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print('📊 모델 설정: $_modelConfig');
      }
    } catch (e) {
      print('❌ 모델 로딩 실패: $e');
      rethrow;
    }
  }

  /// 모델 준비 상태 확인
  bool get isReady => _interpreter != null && _modelConfig != null;

  /// 탐지 일시 중지 (촬영 중 등)
  void pauseDetection() {
    _isPaused = true;
    if (kDebugMode) {
      // ignore: avoid_print
      print('⏸️ 탐지 일시 중지');
    }
  }

  /// 탐지 재개
  void resumeDetection() {
    _isPaused = false;
    if (kDebugMode) {
      // ignore: avoid_print
      print('▶️ 탐지 재개');
    }
  }

  /// 탐지 일시 중지 상태 확인
  bool get isPaused => _isPaused;

  /// 카메라 프레임에서 결함 탐지
  Future<List<DetectedDefect>> detectOnFrame({
    required CameraImage cameraImage,
  }) async {
    if (!isReady) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('❌ 모델이 초기화되지 않음');
      }
      return const <DetectedDefect>[];
    }

    // 프레임 스킵 로직
    _frameCounter++;

    // 탐지가 일시 중지된 경우 스킵
    if (_isPaused) {
      return _lastDetections; // 스킵 시 마지막 결과 유지
    }

    // 이미 처리 중이면 스킵
    if (_isProcessing) {
      _consecutiveSkips++;
      return _lastDetections; // 스킵 시 마지막 결과 유지
    }

    // 시간 기반 스킵 (너무 빠른 연속 처리 방지)
    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _minProcessInterval) {
      _consecutiveSkips++;
      return _lastDetections; // 스킵 시 마지막 결과 유지
    }

    // 프레임 기반 스킵 (5프레임마다 1번 처리)
    if (_frameCounter - _lastProcessedFrame < _frameSkipInterval) {
      _consecutiveSkips++;
      return _lastDetections; // 스킵 시 마지막 결과 유지
    }

    // 연속 스킵이 너무 많으면 강제로 처리
    if (_consecutiveSkips >= _maxConsecutiveSkips) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('⚠️ 연속 스킵이 너무 많아서 강제로 처리합니다. ($_consecutiveSkips회)');
      }
      _consecutiveSkips = 0;
    }

    _lastProcessedFrame = _frameCounter;
    _lastProcessTime = now;
    _isProcessing = true;
    _consecutiveSkips = 0; // 처리 시작 시 연속 스킵 카운터 리셋

    try {
      // silent
      // 원본 이미지 크기 저장
      final originalWidth = cameraImage.width;
      final originalHeight = cameraImage.height;
      // silent

      // 종횡비 계산 (패딩 정보 계산용)
      final modelInputSize = PCBDefectModelConfig.inputSize.toDouble();
      final scale = math.min(
        modelInputSize / originalWidth,
        modelInputSize / originalHeight,
      );
      final newWidth = (originalWidth * scale).round();
      final newHeight = (originalHeight * scale).round();
      final padX = (modelInputSize - newWidth) / 2;
      final padY = (modelInputSize - newHeight) / 2;

      // 1. 이미지 전처리
      final input = preprocessImage(cameraImage, modelInputSize);

      // 2. 모델 추론 실행
      final output = await _runInferenceAsync(
        input,
        _interpreter!,
        _modelConfig!,
      );

      // 3. 결과 후처리
      var detections = postprocessOutputAdvanced(
        output,
        originalWidth,
        originalHeight,
        _modelConfig!.outputShape,
        _modelConfig!.needsTranspose,
        _modelConfig!.hasObjectness,
        PCBDefectModelConfig.classLabels,
        scale: scale,
        padX: padX,
        padY: padY,
        minConfidence: PCBDefectModelConfig.confidenceThreshold,
        nmsThreshold: PCBDefectModelConfig.nmsThreshold,
        agnosticNms: PCBDefectModelConfig.agnosticNms,
        maxDetections: PCBDefectModelConfig.maxDetections,
      );

      // Android 실시간 프레임: 박스 좌표 180도 회전 적용 (촬영/갤러리는 원본 유지)
      if (Platform.isAndroid) {
        detections = detections
            .map(
              (d) => DetectedDefect(
                label: d.label,
                confidence: d.confidence,
                bbox: RectLike(
                  left: originalWidth - d.bbox.left - d.bbox.width,
                  top: originalHeight - d.bbox.top - d.bbox.height,
                  width: d.bbox.width,
                  height: d.bbox.height,
                ),
                sourceWidth: d.sourceWidth,
                sourceHeight: d.sourceHeight,
                detectedAt: d.detectedAt,
              ),
            )
            .toList();
      }

      // silent

      // 성공 시 캐시 업데이트 (박스 유지 강화)
      _lastDetections = detections;
      return detections;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('❌ 탐지 오류: $e');
      }
      // 오류 발생 시에도 직전 결과 유지하여 박스가 사라지지 않도록 함
      return _lastDetections;
    } finally {
      _isProcessing = false; // 처리 완료 플래그 해제
    }
  }

  /// 갤러리 이미지 파일 경로로 탐지 수행
  Future<List<DetectedDefect>> detectOnImagePath(String imagePath) async {
    if (!isReady) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('❌ 모델이 초기화되지 않음');
      }
      return const <DetectedDefect>[];
    }

    // 이미 처리 중이면 스킵
    if (_isProcessing) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('⚠️ 이미 처리 중입니다. 갤러리 이미지 탐지를 스킵합니다.');
      }
      return const <DetectedDefect>[];
    }

    _isProcessing = true; // 처리 시작 플래그 설정

    try {
      if (kDebugMode) {
        // ignore: avoid_print
        print('🖼️ 갤러리 이미지 파일 읽기: $imagePath');
      }

      // 이미지 파일 읽기
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('❌ 이미지를 디코딩할 수 없습니다.');
        }
        return [];
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('🖼️ 이미지 디코딩 성공: ${image.width}x${image.height}');
      }

      final originalWidth = image.width;
      final originalHeight = image.height;

      // 종횡비 유지를 위한 리사이즈 및 패딩 (Letterbox)
      final modelInputSize = PCBDefectModelConfig.inputSize.toDouble();
      final scale = math.min(
        modelInputSize / originalWidth,
        modelInputSize / originalHeight,
      );
      final newWidth = (originalWidth * scale).round();
      final newHeight = (originalHeight * scale).round();

      final resized = img.copyResize(image, width: newWidth, height: newHeight);

      final padX = (modelInputSize - newWidth) / 2;
      final padY = (modelInputSize - newHeight) / 2;

      final paddedImage = img.Image(
        width: modelInputSize.round(),
        height: modelInputSize.round(),
      );
      paddedImage.clear(img.ColorRgb8(0, 0, 0)); // 검은색으로 패딩
      img.compositeImage(
        paddedImage,
        resized,
        dstX: padX.round(),
        dstY: padY.round(),
      );

      // Float32List로 변환하고 정규화
      final input = Float32List(
        1 * modelInputSize.round() * modelInputSize.round() * 3,
      );
      int bufferIndex = 0;
      for (var y = 0; y < paddedImage.height; y++) {
        for (var x = 0; x < paddedImage.width; x++) {
          final pixel = paddedImage.getPixel(x, y);
          input[bufferIndex++] = pixel.r / 255.0;
          input[bufferIndex++] = pixel.g / 255.0;
          input[bufferIndex++] = pixel.b / 255.0;
        }
      }

      // 모델 추론 실행
      final output = await _runInferenceAsync(
        input,
        _interpreter!,
        _modelConfig!,
      );

      // 결과 후처리
      final detections = postprocessOutputAdvanced(
        output,
        originalWidth,
        originalHeight,
        _modelConfig!.outputShape,
        _modelConfig!.needsTranspose,
        _modelConfig!.hasObjectness,
        PCBDefectModelConfig.classLabels,
        scale: scale,
        padX: padX,
        padY: padY,
        minConfidence: PCBDefectModelConfig.confidenceThreshold,
        nmsThreshold: PCBDefectModelConfig.nmsThreshold,
        agnosticNms: PCBDefectModelConfig.agnosticNms,
        maxDetections: PCBDefectModelConfig.maxDetections,
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print('🖼️ 갤러리 이미지 탐지 완료: ${detections.length}개 탐지됨');
        if (detections.isNotEmpty) {
          // ignore: avoid_print
          print(
            '🖼️ 첫 번째 탐지: ${detections.first.label} (${(detections.first.confidence * 100).toStringAsFixed(1)}%)',
          );
        }
      }

      return detections;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('❌ 갤러리 이미지 탐지 오류: $e');
      }
      return [];
    } finally {
      _isProcessing = false; // 처리 완료 플래그 해제
    }
  }

  /// 모델 추론 실행
  Future<Float32List> _runInferenceAsync(
    Float32List input,
    Interpreter interpreter,
    ModelConfig modelConfig,
  ) async {
    // 추론 실행 전 추가 검증
    if (_isPaused) {
      return _createFallbackOutput(modelConfig);
    }

    try {
      // 입력/출력 텐서 정보 확인
      final inputTensor = interpreter.getInputTensor(0);
      final inputShape = inputTensor.shape;
      final outputCount = interpreter.getOutputTensors().length;
      final outputTensor0 = interpreter.getOutputTensor(0);
      final outputShape0 = outputTensor0.shape;
      final outputSize0 = outputShape0.reduce((a, b) => a * b);

      List<List<List<List<double>>>> inputData = _createInputTensor(
        input,
        inputShape,
      );

      // 출력 0 (Detection head) 버퍼 생성
      Object outputData0;
      if (outputShape0.length == 3) {
        // [1, 40, 8400] 형식
        final batch = outputShape0[0];
        final features = outputShape0[1];
        final detections = outputShape0[2];
        outputData0 = List<List<List<double>>>.generate(
          batch,
          (_) => List<List<double>>.generate(
            features,
            (_) => List<double>.filled(detections, 0.0, growable: true),
            growable: true,
          ),
          growable: true,
        );
      } else {
        // 1차원 배열
        outputData0 = Float32List(outputSize0);
      }

      // 출력 1 (Segmentation prototype) 버퍼 생성 (있는 경우)
      Object? outputData1;
      if (outputCount > 1) {
        try {
          final outputTensor1 = interpreter.getOutputTensor(1);
          final outputShape1 = outputTensor1.shape;
          final outputSize1 = outputShape1.reduce((a, b) => a * b);

          if (outputShape1.length == 4) {
            // [1, 160, 160, 32] 형식 (세그멘테이션 프로토타입)
            final batch = outputShape1[0];
            final height = outputShape1[1];
            final width = outputShape1[2];
            final channels = outputShape1[3];
            outputData1 = List.generate(
              batch,
              (_) => List.generate(
                height,
                (_) => List.generate(
                  width,
                  (_) => List<double>.filled(channels, 0.0, growable: true),
                  growable: true,
                ),
                growable: true,
              ),
              growable: true,
            );
          } else {
            // 1차원 배열
            outputData1 = Float32List(outputSize1);
          }
        } catch (e) {
          print('⚠️ 출력 1 버퍼 생성 중 오류: $e');
          // 오류 시 더미 버퍼 생성
          outputData1 = Float32List(819200);
        }
      }

      // 다중 출력으로 모델 실행 (tflite_flutter 공식 API 사용)
      if (outputData1 != null) {
        // runForMultipleInputs 사용: List<Object> inputs, Map<int, Object> outputs
        final inputs = [inputData];
        final outputs = {0: outputData0, 1: outputData1};
        interpreter.runForMultipleInputs(inputs, outputs);
      } else {
        interpreter.run(inputData, outputData0);
      }

      // 출력 0을 1차원으로 변환하여 반환
      final output = Float32List(outputSize0);

      if (outputShape0.length == 3) {
        final outputData0List = outputData0 as List<List<List<double>>>;
        int index = 0;
        for (int i = 0; i < outputData0List.length; i++) {
          final featList = outputData0List[i];
          for (int j = 0; j < featList.length; j++) {
            final detList = featList[j];
            for (int k = 0; k < detList.length; k++) {
              if (index < outputSize0) {
                output[index++] = detList[k];
              }
            }
          }
        }
      } else {
        final outputData0Float = outputData0 as Float32List;
        for (int i = 0; i < outputSize0; i++) {
          output[i] = outputData0Float[i];
        }
      }

      // 모델 출력 검증
      if (output.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('⚠️ 모델 출력이 비어있습니다!');
        }
        return _createFallbackOutput(modelConfig);
      }

      return output;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('❌ 모델 추론 오류: $e');
      }
      return _createFallbackOutput(modelConfig);
    }
  }

  /// 입력 텐서 생성
  List<List<List<List<double>>>> _createInputTensor(
    Float32List input,
    List<int> inputShape,
  ) {
    if (inputShape.length == 4) {
      // [1, 640, 640, 3] 형식으로 변환
      return List.generate(
        1,
        (i) => List.generate(
          PCBDefectModelConfig.inputSize,
          (j) => List.generate(
            PCBDefectModelConfig.inputSize,
            (k) => List.generate(
              3,
              (l) => input[(j * PCBDefectModelConfig.inputSize + k) * 3 + l],
            ),
          ),
        ),
      );
    } else {
      // 1차원 배열을 4차원으로 변환 (기본값)
      return List.generate(
        1,
        (i) => List.generate(
          PCBDefectModelConfig.inputSize,
          (j) => List.generate(
            PCBDefectModelConfig.inputSize,
            (k) => List.generate(
              3,
              (l) => input[(j * PCBDefectModelConfig.inputSize + k) * 3 + l],
            ),
          ),
        ),
      );
    }
  }

  /// 폴백 출력 생성
  Float32List _createFallbackOutput(ModelConfig modelConfig) {
    final size =
        modelConfig.numDetections *
        (modelConfig.numClasses + 5); // obj_score 포함 +5
    if (kDebugMode) {
      // ignore: avoid_print
      print('🔧 Fallback 출력 생성: 크기 $size');
    }
    return Float32List(size);
  }

  /// 리소스 해제
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _modelConfig = null;

    // 프레임 카운터 초기화
    _frameCounter = 0;
    _lastProcessedFrame = 0;
    _lastProcessTime = null;
    _isProcessing = false;
    _isPaused = false;
    _consecutiveSkips = 0;

    if (kDebugMode) {
      // ignore: avoid_print
      print('🧹 DetectorService 정리 완료');
    }
  }
}
