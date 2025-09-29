import 'dart:typed_data';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import '../models/pcb_defect_models.dart';

/// Sigmoid 함수 (로짓 값을 확률로 변환)
@pragma('vm:prefer-inline')
double sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

/// 안전한 리스트 접근 함수
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

/// 카메라 이미지 전처리: YUV→RGB 변환 및 정규화
Float32List preprocessImage(CameraImage cameraImage, double modelInputSize) {
  try {
    final originalWidth = cameraImage.width;
    final originalHeight = cameraImage.height;
    
    // 종횡비 유지를 위한 리사이즈 및 패딩 (Letterbox)
    final scale = math.min(modelInputSize / originalWidth, modelInputSize / originalHeight);
    final newWidth = (originalWidth * scale).round();
    final newHeight = (originalHeight * scale).round();
    
    final padX = (modelInputSize - newWidth) / 2;
    final padY = (modelInputSize - newHeight) / 2;
    
    // 모델 입력 배열 생성
    final input = Float32List(modelInputSize.round() * modelInputSize.round() * 3);
    int bufferIndex = 0;
    const double normalizer = 1.0 / 255.0;
    
    // 최적화된 YUV→RGB 변환으로 모델 입력 생성
    for (int y = 0; y < modelInputSize.round(); y++) {
      for (int x = 0; x < modelInputSize.round(); x++) {
        int r, g, b;
        
        // 패딩 영역인지 확인
        if (x < padX || x >= (padX + newWidth) || 
            y < padY || y >= (padY + newHeight)) {
          // 패딩 영역: 검은색
          r = g = b = 0;
        } else {
          // 실제 이미지 영역: 스케일링된 좌표로 샘플링
          final srcX = ((x - padX) / scale).clamp(0.0, originalWidth - 1.0).toInt();
          final srcY = ((y - padY) / scale).clamp(0.0, originalHeight - 1.0).toInt();
          
          // 최적화된 YUV→RGB 변환
          final rgb = getRgbFromCameraImage(cameraImage, srcX, srcY);
          r = rgb[0];
          g = rgb[1];
          b = rgb[2];
        }
        
        input[bufferIndex++] = r * normalizer;
        input[bufferIndex++] = g * normalizer;
        input[bufferIndex++] = b * normalizer;
      }
    }
    
    return input;
  } catch (e) {
    print('이미지 전처리 오류: $e');
    return Float32List(640 * 640 * 3);
  }
}

/// 최적화된 YUV→RGB 변환 함수 (좌표 회전 문제 해결)
@pragma('vm:prefer-inline')
List<int> getRgbFromCameraImage(CameraImage image, int x, int y) {
  final width = image.width;
  final height = image.height;
  
  if (x < 0 || x >= width || y < 0 || y >= height) {
    return [0, 0, 0];
  }
  
  // 원본 좌표 사용 (UI에서 좌표 변환 처리)
  final int rotatedX = x;
  final int rotatedY = y;
  
  final yPlane = image.planes[0].bytes;
  final uPlane = image.planes[1].bytes;
  final vPlane = image.planes[2].bytes;
  
  final yRowStride = image.planes[0].bytesPerRow;
  final uRowStride = image.planes[1].bytesPerRow;
  final vRowStride = image.planes[2].bytesPerRow;
  final uPixelStride = image.planes[1].bytesPerPixel ?? 1;
  final vPixelStride = image.planes[2].bytesPerPixel ?? 1;

  final uvx = rotatedX >> 1;
  final uvy = rotatedY >> 1;

  final yIndex = rotatedY * yRowStride + rotatedX;
  final uIndex = uvy * uRowStride + uvx * uPixelStride;
  final vIndex = uvy * vRowStride + uvx * vPixelStride;

  final int Y = yPlane[yIndex];
  final int U = uPlane[uIndex];
  final int V = vPlane[vIndex];

  // ITU-R BT.601 변환 (정수 연산으로 최적화)
  final int C = Y - 16;
  final int D = U - 128;
  final int E = V - 128;

  int r = (298 * C + 409 * E + 128) >> 8;
  int g = (298 * C - 100 * D - 208 * E + 128) >> 8;
  int b = (298 * C + 516 * D + 128) >> 8;

  r = r < 0 ? 0 : (r > 255 ? 255 : r);
  g = g < 0 ? 0 : (g > 255 ? 255 : g);
  b = b < 0 ? 0 : (b > 255 ? 255 : b);

  return [r, g, b];
}

/// 출력 텐서 변환 함수 (Transpose 필요한 경우)
List<List<double>> transposeOutput(Float32List output, List<int> shape) {
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

/// 출력 텐서 직접 변환 함수 (Transpose 불필요한 경우)
List<List<double>> directReshape(Float32List output, List<int> shape) {
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

/// IoU (Intersection over Union) 계산
double calculateIoU(RectLike box1, RectLike box2) {
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

/// 탐지 오류 처리
List<DetectedDefect> handleDetectionError(dynamic error, int width, int height) {
  print('🔧 에러 복구 시도: $error');
  print('❗ 상세 에러: ${error.toString()}');

  // 모든 에러에 대해 빈 리스트 반환 (더미 탐지 제거)
  print('🛠️ 안전 모드로 전환 - 탐지 결과 없음');
  return <DetectedDefect>[];
}
