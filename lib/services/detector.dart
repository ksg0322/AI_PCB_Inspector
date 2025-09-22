import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

class DetectedDefect {
  final String label;
  final double confidence;
  final RectLike bbox;
  final int sourceWidth;
  final int sourceHeight;

  DetectedDefect({
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.sourceWidth,
    required this.sourceHeight,
  });
}

class RectLike {
  final double left;
  final double top;
  final double width;
  final double height;

  const RectLike({required this.left, required this.top, required this.width, required this.height});
}

class DetectorService {
  Interpreter? _interpreter;
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.3; // 정확한 탐지만 허용
  static const double nmsThreshold = 0.3; // 중복 탐지 방지 더 강화

  static const List<String> classLabels = [
    'Dry_joint',
    'Incorrect_installation', 
    'PCB_damage',
    'Short_circuit'
  ];

  int? _numClasses;
  int? _numDetections;
  bool _needsTranspose = false;
  bool _hasObjectness = true; // 출력에 objectness가 존재하는지 여부
  int _numMaskCoeffs = 0;     // seg 모델의 마스크 계수 개수(미사용 시 0)

  Future<void> initialize() async {
    if (_interpreter != null) return;

    try {
      print('🔧 AI 모델 로딩 중...');

      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false; // 안정성 향상을 위해 비활성화

      final interpreter = await Interpreter.fromAsset(
        'assets/best_float16.tflite',
        options: options
      );

      _interpreter = interpreter;

      await _validateAndConfigureModel();

      // 모델 정보 상세 출력
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      
      print('📊 모델 정보 상세:');
      print('  - 입력 텐서 수: ${inputTensors.length}');
      for (int i = 0; i < inputTensors.length; i++) {
        final tensor = inputTensors[i];
        print('    입력 $i: ${tensor.shape} (${tensor.type})');
      }
      
      print('  - 출력 텐서 수: ${outputTensors.length}');
      for (int i = 0; i < outputTensors.length; i++) {
        final tensor = outputTensors[i];
        print('    출력 $i: ${tensor.shape} (${tensor.type})');
      }
      
      print('✅ 모델 로딩 및 구성 완료!');

    } catch (e) {
      print('❌ 모델 로딩 실패: $e');
      rethrow;
    }
  }

  Future<void> _validateAndConfigureModel() async {
    if (_interpreter == null) return;

    try {
      // 모델 입력/출력 정보 확인
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      final inputShape = inputTensor.shape;
      final outputShape = outputTensor.shape;

      print('📥 입력 형식: $inputShape');
      print('📤 출력 형식: $outputShape');
      print('📊 입력 데이터 타입: ${inputTensor.type}');
      print('📊 출력 데이터 타입: ${outputTensor.type}');

      // 모델 호환성 검사
      if (inputShape.length != 4 || inputShape[1] != 640 || inputShape[2] != 640 || inputShape[3] != 3) {
        print('⚠️ 입력 형식이 예상과 다릅니다: $inputShape');
      }

      if (outputShape.length == 3 && outputShape[1] < outputShape[2]) {
        // [1, 40, 8400] 형태 - transpose 필요
        _needsTranspose = true;
        _numDetections = outputShape[2];
        final features = outputShape[1];
        // YOLOv8n-seg 모델: features = 4(box) + 1(obj) + 4(classes) + 32(mask_coeffs) = 41
        // 하지만 TFLite 변환 시 objectness가 제거될 수 있음: 4 + 4 + 32 = 40
        _numClasses = classLabels.length; // 4개 고정
        final remaining = features - 4 - _numClasses!; // 40 - 4 - 4 = 32
        
        if (remaining == 32) {
          // YOLOv8n-seg: 4(box) + 4(classes) + 32(masks) = 40 (objectness 없음)
          // 또는 4(box) + 1(obj) + 4(classes) + 31(masks) = 40 (objectness 있음)
          // 안전하게 objectness 없음으로 시작
          _hasObjectness = false;
          _numMaskCoeffs = 32;
        } else if (remaining == 33) {
          // objectness + 마스크 계수
          _hasObjectness = true;
          _numMaskCoeffs = 32;
        } else {
          // 일반 검출 모델
          _hasObjectness = true;
          _numMaskCoeffs = 0;
        }
        print('🔄 Transpose 모드 활성화: [1, ${outputShape[1]}, ${outputShape[2]}] → [1, ${outputShape[2]}, ${outputShape[1]}]');
      } else if (outputShape.length == 3) {
        // [1, 8400, 40] 형태 - transpose 불필요
        _needsTranspose = false;
        _numDetections = outputShape[1];
        final features = outputShape[2];
        _numClasses = classLabels.length; // 4개 고정
        final remaining = features - 4 - _numClasses!;
        
        if (remaining == 32) {
          // YOLOv8n-seg: 4(box) + 4(classes) + 32(masks) = 40 (objectness 없음)
          _hasObjectness = false;
          _numMaskCoeffs = 32;
        } else if (remaining == 33) {
          _hasObjectness = true;
          _numMaskCoeffs = 32;
        } else {
          _hasObjectness = true;
          _numMaskCoeffs = 0;
        }
        print('✅ Direct 모드: transpose 불필요');
      } else {
        // 기본값 설정
        _numDetections = 8400;
        _numClasses = classLabels.length;
        print('⚠️ 알 수 없는 출력 형식, 기본값 사용');
      }

      print('🎯 설정: 클래스 수=$_numClasses, 탐지 수=$_numDetections, objectness=$_hasObjectness, maskCoeffs=$_numMaskCoeffs');

    } catch (e) {
      print('❌ 모델 검증 실패: $e');
      // 기본값으로 대체
      _numDetections = 8400;
      _numClasses = classLabels.length;
      _needsTranspose = true;
    }
  }

  bool get isReady => _interpreter != null;

  // Sigmoid helper for logits fallback
  @pragma('vm:prefer-inline')
  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  T? safeAccess<T>(List<dynamic>? list, int index, [T? defaultValue]) {
    try {
      if (list == null || index < 0 || index >= list.length) {
        return defaultValue;
      }
      return list[index] as T? ?? defaultValue;
    } catch (e) {
      print('🛡️ Safe access 실패 at index $index: $e');
      return defaultValue;
    }
  }

  Future<List<DetectedDefect>> detectOnFrame({
    required CameraImage cameraImage,
  }) async {
    if (_interpreter == null) {
      print('❌ 모델이 초기화되지 않음');
      return const <DetectedDefect>[];
    }

    try {
      // 원본 이미지 크기 저장
      final originalWidth = cameraImage.width;
      final originalHeight = cameraImage.height;
      
      // 종횡비 계산 (패딩 정보 계산용)
      final modelInputSize = 640.0;
      final scale = math.min(modelInputSize / originalWidth, modelInputSize / originalHeight);
      final newWidth = (originalWidth * scale).round();
      final newHeight = (originalHeight * scale).round();
      final padX = (modelInputSize - newWidth) / 2;
      final padY = (modelInputSize - newHeight) / 2;
      
      print('📏 카메라 이미지 크기: $originalWidth x $originalHeight → 모델 입력: 640 x 640 (스케일: $scale)');
      
      // 1. 이미지 전처리 (YUV to RGB, 리사이즈, 정규화)
      final input = _preprocessImage(cameraImage);

      // 2. 모델 추론 실행
      final output = await _runInferenceAsync(input);

      // 3. 결과 후처리 (패딩 및 스케일 정보 전달)
      final detections = _postprocessOutputAdvanced(
        output, 
        originalWidth, 
        originalHeight,
        scale: scale,
        padX: padX,
        padY: padY
      );

      if (detections.isNotEmpty) {
        print('🎯 ${detections.length}개 결함 탐지: ${detections.map((d) => '${d.label}(${(d.confidence * 100).toInt()}%)').join(', ')}');
      } else {
        print('⚠️ 탐지된 결함이 없습니다. 임계값: $confidenceThreshold');
      }

      return detections;

    } catch (e) {
      print('❌ 탐지 오류: $e');
      return _handleDetectionError(e, cameraImage.width, cameraImage.height);
    }
  }

  // 갤러리 이미지 파일 경로로 탐지 수행
  Future<List<DetectedDefect>> detectOnImagePath(String imagePath) async {
    if (_interpreter == null) {
      print('❌ 모델이 초기화되지 않음');
      return const [];
    }

    try {
      // 1. 이미지 파일 읽기
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        print('❌ 이미지를 디코딩할 수 없습니다.');
        return [];
      }
      
      final originalWidth = image.width;
      final originalHeight = image.height;

      // 2. 종횡비 유지를 위한 리사이즈 및 패딩 (Letterbox)
      final modelInputSize = 640.0;
      final scale = math.min(modelInputSize / originalWidth, modelInputSize / originalHeight);
      final newWidth = (originalWidth * scale).round();
      final newHeight = (originalHeight * scale).round();

      final resized = img.copyResize(image, width: newWidth, height: newHeight);

      final padX = (modelInputSize - newWidth) / 2;
      final padY = (modelInputSize - newHeight) / 2;

      final paddedImage = img.Image(width: modelInputSize.round(), height: modelInputSize.round());
      paddedImage.clear(img.ColorRgb8(0, 0, 0)); // 검은색으로 패딩
      img.compositeImage(paddedImage, resized, dstX: padX.round(), dstY: padY.round());

      // 3. Float32List로 변환하고 정규화
      final input = Float32List(1 * modelInputSize.round() * modelInputSize.round() * 3);
      int bufferIndex = 0;
      for (var y = 0; y < paddedImage.height; y++) {
        for (var x = 0; x < paddedImage.width; x++) {
          final pixel = paddedImage.getPixel(x, y);
          input[bufferIndex++] = pixel.r / 255.0;
          input[bufferIndex++] = pixel.g / 255.0;
          input[bufferIndex++] = pixel.b / 255.0;
        }
      }

      // 4. 모델 추론 실행
      final output = await _runInferenceAsync(input);

      // 디버깅: 모델 출력 분석
      print('🔍 [DEBUG] 모델 출력 크기: ${output.length}');
      print('🔍 [DEBUG] 첫 10개 값: ${output.take(10).toList()}');
      if (output.isNotEmpty) {
        print('🔍 [DEBUG] 최대값: ${output.reduce(math.max)}');
        print('🔍 [DEBUG] 최소값: ${output.reduce(math.min)}');
        
        // 신뢰도별 값 분포 분석
        final highValues = <int>[];
        final mediumValues = <int>[];
        final lowValues = <int>[];
        
        for (int i = 0; i < output.length; i++) {
          if (output[i] > 0.5) highValues.add(i);
          else if (output[i] > 0.1) mediumValues.add(i);
          else if (output[i] > 0.01) lowValues.add(i);
        }
        
        print('🔍 [DEBUG] 신뢰도 분포:');
        print('  - 0.5 이상: ${highValues.length}개');
        print('  - 0.1~0.5: ${mediumValues.length}개');
        print('  - 0.01~0.1: ${lowValues.length}개');
        
        if (highValues.isNotEmpty) {
          print('🔍 [DEBUG] 높은 신뢰도 값들: ${highValues.take(5).map((i) => output[i].toStringAsFixed(3)).toList()}');
        }
        if (mediumValues.isNotEmpty) {
          print('🔍 [DEBUG] 중간 신뢰도 값들: ${mediumValues.take(5).map((i) => output[i].toStringAsFixed(3)).toList()}');
        }
      } else {
        print('🔍 [DEBUG] 출력이 비어있음!');
      }

      // 5. 결과 후처리 (패딩 및 스케일 정보 전달)
      final detections = _postprocessOutputAdvanced(
        output,
        originalWidth,
        originalHeight,
        scale: scale,
        padX: padX,
        padY: padY,
      );

      print('🖼️ 갤러리 이미지 탐지 완료: ${detections.length}개 발견');
      return detections;

    } catch (e) {
      print('❌ 갤러리 이미지 탐지 오류: $e');
      return [];
    }
  }

  // 이미지 전처리: YUV420 -> RGB -> 종횡비 유지 리사이즈 -> 정규화
  Float32List _preprocessImage(CameraImage cameraImage) {
    try {
      // YUV -> RGB 변환
      final image = _convertYUV420ToImage(cameraImage);
      
      final originalWidth = image.width;
      final originalHeight = image.height;
      
      // 종횡비 유지를 위한 리사이즈 및 패딩 (Letterbox)
      final modelInputSize = 640.0;
      final scale = math.min(modelInputSize / originalWidth, modelInputSize / originalHeight);
      final newWidth = (originalWidth * scale).round();
      final newHeight = (originalHeight * scale).round();
      
      final resized = img.copyResize(image, width: newWidth, height: newHeight);
      
      final padX = (modelInputSize - newWidth) / 2;
      final padY = (modelInputSize - newHeight) / 2;
      
      final paddedImage = img.Image(width: modelInputSize.round(), height: modelInputSize.round());
      paddedImage.clear(img.ColorRgb8(0, 0, 0)); // 검은색으로 패딩
      img.compositeImage(paddedImage, resized, dstX: padX.round(), dstY: padY.round());
      
      // Float32List로 변환하고 정규화
      final input = Float32List(1 * modelInputSize.round() * modelInputSize.round() * 3);
      int bufferIndex = 0;
      
      // 정규화 방식 변경: 0~1 스케일링 + 평균 빼기
      const double normalizer = 1.0 / 255.0;
      
      // YOLOv8 표준 정규화: (픽셀값/255.0 - 0.5) / 0.5 = 픽셀값/127.5 - 1.0
      for (var y = 0; y < paddedImage.height; y++) {
        for (var x = 0; x < paddedImage.width; x++) {
          final pixel = paddedImage.getPixel(x, y);
          // 방법 1: 단순 0~1 스케일링 (기본)
          input[bufferIndex++] = pixel.r * normalizer;
          input[bufferIndex++] = pixel.g * normalizer;
          input[bufferIndex++] = pixel.b * normalizer;
          
          // 방법 2: -1~1 스케일링 (주석 처리됨)
          // input[bufferIndex++] = (pixel.r / 127.5) - 1.0;
          // input[bufferIndex++] = (pixel.g / 127.5) - 1.0;
          // input[bufferIndex++] = (pixel.b / 127.5) - 1.0;
        }
      }
      
      print('🔄 정규화 완료: 0~1 스케일링 적용');
      
      print('🔄 이미지 전처리 완료: $originalWidth x $originalHeight → ${modelInputSize.round()} x ${modelInputSize.round()}, 패딩: $padX, $padY');
      return input;
    } catch (e) {
      print('❌ 이미지 전처리 오류: $e');
      return Float32List(640 * 640 * 3);
    }
  }

  // CameraImage (YUV420_888) to Image (RGB) conversion
  img.Image _convertYUV420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel!;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvx = (x / 2).floor();
        final uvy = (y / 2).floor();

        final yIndex = y * yRowStride + x;
        final uIndex = uvy * uvRowStride + uvx * uvPixelStride;
        final vIndex = uvy * uvRowStride + uvx * uvPixelStride;

        final yValue = yPlane[yIndex];
        final uValue = uPlane[uIndex];
        final vValue = vPlane[vIndex];
        
        // JPEG YUV to RGB conversion
        int r = (yValue + 1.402 * (vValue - 128)).round();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
        int b = (yValue + 1.772 * (uValue - 128)).round();

        out.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }

    return out;
  }

  Future<Float32List> _runInferenceAsync(Float32List input) async {
    if (_interpreter == null) {
      print('❌ 인터프리터가 null입니다');
      return Float32List((_numDetections ?? 8400) * ((_numClasses ?? 4) + 4));
    }

    try {
      // 입력 텐서 형식 확인 및 상세 분석
      final inputTensor = _interpreter!.getInputTensor(0);
      final inputShape = inputTensor.shape;
      print('🔍 실제 입력 형식: $inputShape');
      print('🔍 [DEBUG] 입력 텐서 타입: ${inputTensor.type}');
      print('🔍 [DEBUG] 입력 데이터 크기: ${input.length}');
      print('🔍 [DEBUG] 입력 데이터 범위: ${input.reduce(math.min)} ~ ${input.reduce(math.max)}');
      
      // 입력 데이터 샘플 확인
      print('🔍 [DEBUG] 입력 데이터 샘플: ${input.take(10).map((v) => v.toStringAsFixed(4)).toList()}');

      // 출력 텐서 개수 확인
      final outputCount = _interpreter!.getOutputTensors().length;
      print('🔍 출력 텐서 개수: $outputCount');
      
      // 출력 0 (Detection head) 형식 확인
      final outputTensor0 = _interpreter!.getOutputTensor(0);
      final outputShape0 = outputTensor0.shape;
      final outputSize0 = outputShape0.reduce((a, b) => a * b);
      print('🔍 출력 0 형식: $outputShape0, 크기: $outputSize0');
      print('🧪 텐서 타입 - 입력: ${inputTensor.type}, 출력0: ${outputTensor0.type}');
      
      // 출력 1 (Segmentation prototype) 형식 확인 (있는 경우)
      if (outputCount > 1) {
        try {
          final outputTensor1 = _interpreter!.getOutputTensor(1);
          final outputShape1 = outputTensor1.shape;
          final outputSize1 = outputShape1.reduce((a, b) => a * b);
          print('🔍 출력 1 형식: $outputShape1, 크기: $outputSize1');
        } catch (e) {
          print('⚠️ 출력 1 확인 중 오류: $e');
        }
      }

      List<List<List<List<double>>>> inputData = _createInputTensor(input, inputShape);

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
          final outputTensor1 = _interpreter!.getOutputTensor(1);
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
        _interpreter!.runForMultipleInputs(inputs, outputs);
      } else {
        _interpreter!.run(inputData, outputData0);
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
      
      print('✅ 모델 추론 성공');
      
      // 모델 출력 검증 및 상세 분석
      if (output.isEmpty) {
        print('⚠️ 모델 출력이 비어있습니다!');
        return _createFallbackOutput();
      }
      
      final maxValue = output.reduce(math.max);
      final minValue = output.reduce(math.min);
      print('🔍 모델 출력 범위: $minValue ~ $maxValue');
      
      // 출력값 분포 분석
      int zeroCount = 0;
      int smallCount = 0;
      int mediumCount = 0;
      int largeCount = 0;
      
      for (int i = 0; i < output.length; i++) {
        final value = output[i];
        if (value == 0) zeroCount++;
        else if (value < 0.01) smallCount++;
        else if (value < 0.1) mediumCount++;
        else largeCount++;
      }
      
      print('🔍 모델 출력 분포:');
      print('  - 0: $zeroCount개 (${(zeroCount / output.length * 100).toStringAsFixed(1)}%)');
      print('  - 0~0.01: $smallCount개 (${(smallCount / output.length * 100).toStringAsFixed(1)}%)');
      print('  - 0.01~0.1: $mediumCount개 (${(mediumCount / output.length * 100).toStringAsFixed(1)}%)');
      print('  - 0.1 이상: $largeCount개 (${(largeCount / output.length * 100).toStringAsFixed(1)}%)');
      
      if (maxValue < 0.01) {
        print('⚠️ 모델 출력값이 모두 매우 낮습니다. 모델이 제대로 동작하지 않을 수 있습니다.');
      } else if (largeCount > 0) {
        print('✅ 모델이 유의미한 출력값을 생성했습니다.');
      }
      
      return output;

    } catch (e) {
      print('❌ 모델 추론 오류: $e');
      return _createFallbackOutput();
    }
  }

  List<List<List<List<double>>>> _createInputTensor(Float32List input, List<int> inputShape) {
    if (inputShape.length == 4) {
      // [1, 640, 640, 3] 형식으로 변환
      return List.generate(1, (i) =>
        List.generate(640, (j) =>
          List.generate(640, (k) =>
            List.generate(3, (l) =>
              input[(j * 640 + k) * 3 + l]
            )
          )
        )
      );
    } else {
      // 1차원 배열을 4차원으로 변환 (기본값)
      return List.generate(1, (i) =>
        List.generate(640, (j) =>
          List.generate(640, (k) =>
            List.generate(3, (l) =>
              input[(j * 640 + k) * 3 + l]
            )
          )
        )
      );
    }
  }

  Float32List _createFallbackOutput() {
    final size = (_numDetections ?? 8400) * ((_numClasses ?? 4) + 5); // obj_score 포함 +5
    print('🔧 Fallback 출력 생성: 크기 $size');
    return Float32List(size);
  }

  List<DetectedDefect> _postprocessOutputAdvanced(
    Float32List output,
    int originalWidth,
    int originalHeight,
    {double scale = 1.0, double padX = 0.0, double padY = 0.0}
  ) {
    final detections = <DetectedDefect>[];

    if (_interpreter == null) {
      print('❌ 후처리: 인터프리터가 null입니다');
      return detections;
    }

    try {
      // 실제 모델 출력 형식에 따라 동적으로 파싱
      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      print('🔍 후처리 - 출력 형식: $outputShape');
      
      // 출력 형식 상세 분석
      print('🔍 [DEBUG] 출력 텐서 타입: ${outputTensor.type}');
      print('🔍 [DEBUG] 출력 텐서 차원: ${outputShape.length}차원');
      print('🔍 [DEBUG] 출력 텐서 크기: ${outputShape.join(" x ")}');
      print('🔍 [DEBUG] 출력 배열 크기: ${output.length}');
      
      // 출력 배열 샘플 값 확인
      if (output.length > 0) {
        print('🔍 [DEBUG] 첫 10개 값: ${output.take(10).map((v) => v.toStringAsFixed(4)).toList()}');
      }

      List<List<double>> processedOutput;

      if (_needsTranspose) {
        processedOutput = _transposeOutput(output, outputShape);
        print('🔄 Transpose 적용됨');
      } else {
        processedOutput = _directReshape(output, outputShape);
        print('✅ Direct reshape 적용됨');
      }
      
      // 처리된 출력 샘플 확인
      if (processedOutput.isNotEmpty && processedOutput[0].length > 0) {
        print('🔍 [DEBUG] 처리된 출력 첫 행 샘플: ${processedOutput[0].take(10).map((v) => v.toStringAsFixed(4)).toList()}');
      }

      print('🔍 [DEBUG] 처리할 탐지 수: ${processedOutput.length}');
      
      // 각 탐지 결과 처리
      int validDetections = 0;
      int passingObjectness = 0;
      int passingFinalConfidence = 0;
      
      for (int i = 0; i < processedOutput.length; i++) {
        final detection = processedOutput[i];

        if (detection.length < 5) continue;
        validDetections++;

        // YOLOv8n-seg 헤드 해석: [cx, cy, w, h, cls0, cls1, cls2, cls3, mask_coeffs...]
        final objIndex = 4;
        final classStart = _hasObjectness ? 5 : 4; // objectness 유무에 따라 조정
        final classEnd = classStart + 4; // 4개 클래스 고정
        final objectness = _hasObjectness ? detection[objIndex] : 1.0;
        
        // objectness가 로짓 형태일 수 있으므로 sigmoid 적용
        final objScore = (objectness < 0.0 || objectness > 1.0) ? _sigmoid(objectness) : objectness;
        if (objScore < confidenceThreshold) continue;
        passingObjectness++;

        double maxClassConfidence = 0.0;
        int bestClassIndex = -1;

        for (int classIndex = 0; classIndex < 4; classIndex++) {
          final classIdx = classStart + classIndex;
          if (classIdx >= detection.length) break; // 배열 범위 체크
          
          double classConfidence = detection[classIdx];
          // 클래스 확률도 로짓일 수 있으므로 sigmoid 적용
          if (classConfidence < 0.0 || classConfidence > 1.0) {
            classConfidence = _sigmoid(classConfidence);
          }
          if (classConfidence > maxClassConfidence) {
            maxClassConfidence = classConfidence;
            bestClassIndex = classIndex;
          }
        }
        
        // 최종 신뢰도 = objectness * max(class_probability)
        final finalConfidence = objScore * maxClassConfidence;

        // 디버깅: 모든 탐지 후보에 대한 상세 정보
        final debugInfo = '탐지 $i: obj=${objScore.toStringAsFixed(3)}, ' +
                         'maxClass=${maxClassConfidence.toStringAsFixed(3)}, ' +
                         'final=${finalConfidence.toStringAsFixed(3)}, ' +
                         'class=$bestClassIndex (${bestClassIndex >= 0 && bestClassIndex < classLabels.length ? classLabels[bestClassIndex] : "unknown"})';
        
        // 높은 신뢰도 탐지는 항상 출력, 낮은 신뢰도는 처음 몇 개만 출력
        if (finalConfidence > 0.3 || i < 5) {
          print('🔍 [DEBUG] $debugInfo');
        }

        // 최종 신뢰도 임계값 확인
        if (finalConfidence >= confidenceThreshold && bestClassIndex != -1) {
          passingFinalConfidence++;
          
          // 바운딩 박스 좌표 변환 (YOLO 출력 → 픽셀 좌표)
          // YOLO 출력: [center_x, center_y, width, height] (0-1 정규화)
          // YOLOv8n-seg는 항상 0~1 정규화된 값을 출력
          double cx = detection[0];
          double cy = detection[1];
          double bw = detection[2];
          double bh = detection[3];
          
          // 0~1 정규화된 값을 640 픽셀로 변환
          final centerX_padded = cx * 640.0;
          final centerY_padded = cy * 640.0;
          final boxWidth_padded = bw * 640.0;
          final boxHeight_padded = bh * 640.0;
          
          print('🔍 [DEBUG] 박스 좌표(패딩 포함): 중심($centerX_padded, $centerY_padded), 크기($boxWidth_padded, $boxHeight_padded)');

          // 패딩 제거 및 원본 이미지 좌표로 스케일링
          final centerX_original = (centerX_padded - padX) / scale;
          final centerY_original = (centerY_padded - padY) / scale;
          final boxWidth_original = boxWidth_padded / scale;
          final boxHeight_original = boxHeight_padded / scale;
          
          print('🔍 [DEBUG] 박스 좌표(원본): 중심($centerX_original, $centerY_original), 크기($boxWidth_original, $boxHeight_original)');

          final left = centerX_original - boxWidth_original / 2;
          final top = centerY_original - boxHeight_original / 2;
          final width = boxWidth_original;
          final height = boxHeight_original;

          // 좌표 유효성 검사
          if (left < 0 || top < 0 || width <= 0 || height <= 0 ||
              left + width > originalWidth || top + height > originalHeight) {
            print('⚠️ [DEBUG] 유효하지 않은 좌표: left=$left, top=$top, width=$width, height=$height');
            continue;
          }

          // 박스 크기 유효성 검사 (너무 작거나 큰 박스 제거)
          final minBoxSize = 10.0; // 최소 박스 크기
          final maxBoxSize = math.min(originalWidth, originalHeight) * 0.8; // 최대 박스 크기
          if (width < minBoxSize || height < minBoxSize || 
              width > maxBoxSize || height > maxBoxSize) {
            print('⚠️ [DEBUG] 부적절한 박스 크기: width=$width, height=$height (최소: $minBoxSize, 최대: $maxBoxSize)');
            continue;
          }

          // 좌표 정규화 및 클램핑
          final bbox = RectLike(
            left: left.clamp(0.0, originalWidth.toDouble()),
            top: top.clamp(0.0, originalHeight.toDouble()),
            width: width.clamp(0.0, originalWidth.toDouble()),
            height: height.clamp(0.0, originalHeight.toDouble()),
          );

          detections.add(DetectedDefect(
            label: classLabels[bestClassIndex],
            confidence: finalConfidence,
            bbox: bbox,
            sourceWidth: originalWidth,
            sourceHeight: originalHeight,
          ));
        }
      }

      // 디버깅 요약
      print('🔍 [DEBUG] 탐지 단계별 결과:');
      print('  - 유효한 탐지: $validDetections / ${processedOutput.length}');
      print('  - Objectness 통과: $passingObjectness');
      print('  - 최종 신뢰도 통과: $passingFinalConfidence');
      print('  - 좌표 생성된 탐지: ${detections.length}');

      // 더미 탐지 제거 - 실제 탐지만 반환

      // NMS 적용
      final filteredDetections = _applyAdvancedNMS(detections);
      print('🎯 NMS 전: ${detections.length}개, NMS 후: ${filteredDetections.length}개');

      // 최종 탐지 결과 상세 로그
      if (filteredDetections.isNotEmpty) {
        print('🎉 최종 탐지 결과:');
        for (int i = 0; i < filteredDetections.length; i++) {
          final defect = filteredDetections[i];
          print('  탐지 $i: ${defect.label} (${(defect.confidence * 100).toStringAsFixed(1)}%)');
          print('    위치: (${defect.bbox.left.toStringAsFixed(1)}, ${defect.bbox.top.toStringAsFixed(1)})');
          print('    크기: ${defect.bbox.width.toStringAsFixed(1)} x ${defect.bbox.height.toStringAsFixed(1)}');
        }
      } else {
        print('❌ 최종 탐지 결과가 비어있습니다.');
      }

      return filteredDetections;

    } catch (e) {
      print('❌ 후처리 오류: $e');
      return <DetectedDefect>[];
    }
  }

  List<List<double>> _transposeOutput(Float32List output, List<int> shape) {
    final features = shape[1]; // 40
    final detections = shape[2]; // 8400
    final result = <List<double>>[];

    for (int det = 0; det < detections; det++) {
      final detection = <double>[];
      for (int feat = 0; feat < features; feat++) {
        final index = feat * detections + det;
        if (index < output.length) {
          detection.add(output[index]);
        } else {
          detection.add(0.0);
        }
      }
      result.add(detection);
    }

    return result;
  }

  // Direct reshape (transpose 불필요한 경우)
  List<List<double>> _directReshape(Float32List output, List<int> shape) {
    final detections = shape[1]; // 8400  
    final features = shape[2]; // 40
    final result = <List<double>>[];

    for (int det = 0; det < detections; det++) {
      final detection = <double>[];
      for (int feat = 0; feat < features; feat++) {
        final index = det * features + feat;
        if (index < output.length) {
          detection.add(output[index]);
        } else {
          detection.add(0.0);
        }
      }
      result.add(detection);
    }

    return result;
  }

  List<DetectedDefect> _applyAdvancedNMS(List<DetectedDefect> detections) {
    if (detections.isEmpty) return detections;

    // 신뢰도 순으로 정렬
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final keep = <DetectedDefect>[];
    final suppressed = List<bool>.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      keep.add(detections[i]);

      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        // 같은 클래스인지 확인
        if (detections[i].label != detections[j].label) continue;

        // IoU 계산
        final iou = _calculateIoU(detections[i].bbox, detections[j].bbox);
        if (iou > nmsThreshold) {
          suppressed[j] = true;
          print('🗑️ NMS로 제거: ${detections[j].label} (${(detections[j].confidence * 100).toStringAsFixed(1)}%) - IoU: ${iou.toStringAsFixed(3)}');
        }
      }
    }

    return keep;
  }

  // IoU (Intersection over Union) 계산
  double _calculateIoU(RectLike box1, RectLike box2) {
    final x1 = math.max(box1.left, box2.left);
    final y1 = math.max(box1.top, box2.top);
    final x2 = math.min(box1.left + box1.width, box2.left + box2.width);
    final y2 = math.min(box1.top + box1.height, box2.top + box2.height);

    if (x2 <= x1 || y2 <= y1) return 0.0;

    final intersection = (x2 - x1) * (y2 - y1);
    final area1 = box1.width * box1.height;
    final area2 = box2.width * box2.height;
    final union = area1 + area2 - intersection;

    return union > 0 ? intersection / union : 0.0;
  }

  List<DetectedDefect> _handleDetectionError(dynamic error, int width, int height) {
    print('🔧 에러 복구 시도: $error');
    print('❗ 상세 에러: ${error.toString()}');

    // 모든 에러에 대해 빈 리스트 반환 (더미 탐지 제거)
    print('🛠️ 안전 모드로 전환 - 탐지 결과 없음');
    return <DetectedDefect>[];
  }

  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    print('🧹 DetectorService 정리 완료');
  }
}