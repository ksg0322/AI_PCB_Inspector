import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/pcb_defect_models.dart';

class ImageAnnotator {
  /// 결함이 표시된 이미지를 생성
  static Future<String?> createAnnotatedImage({
    required String originalImagePath,
    required List<DetectedDefect> defects,
    required String outputPath,
  }) async {
    try {
      print('🖼️ 결함 주석 이미지 생성 시작: $originalImagePath');
      
      // 원본 이미지 로드
      final originalFile = File(originalImagePath);
      if (!await originalFile.exists()) {
        print('❌ 원본 이미지 파일이 존재하지 않습니다');
        return null;
      }
      
      final imageBytes = await originalFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        print('❌ 이미지 디코딩 실패');
        return null;
      }
      
      print('📏 원본 이미지 크기: ${originalImage.width}x${originalImage.height}');
      
      // 결함 박스 그리기
      final annotatedImage = _drawDefectBoxes(originalImage, defects);
      
      // 주석이 달린 이미지 저장
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(annotatedImage));
      
      print('✅ 결함 주석 이미지 생성 완료: $outputPath');
      return outputPath;
      
    } catch (e) {
      print('❌ 결함 주석 이미지 생성 실패: $e');
      return null;
    }
  }
  
  /// 결함 박스 그리기
  static img.Image _drawDefectBoxes(img.Image originalImage, List<DetectedDefect> defects) {
    final annotatedImage = img.Image.from(originalImage);
    
    for (int i = 0; i < defects.length; i++) {
      final defect = defects[i];
      final bbox = defect.bbox;
      
      // 박스 색상 결정
      final color = _getDefectColor(defect.label);
      
      // 박스 그리기 (앱과 동일한 두께)
      _drawRectangle(
        annotatedImage,
        bbox.left.toInt(),
        bbox.top.toInt(),
        bbox.width.toInt(),
        bbox.height.toInt(),
        color,
        thickness: 2,
      );
      
      // 라벨 텍스트 그리기 (앱과 동일한 위치 - 결함별로 다른 위치)
      final labelPosition = _getLabelPosition(defect.label, defect, i + 1);
      _drawText(
        annotatedImage,
        '${i + 1}',
        labelPosition.left.toInt(),
        labelPosition.top.toInt(),
        color,
      );
    }
    
    return annotatedImage;
  }
  
  /// 결함 종류별 색상 반환 (앱과 동일한 색상)
  static img.Color _getDefectColor(String label) {
    switch (label) {
      case 'Dry_joint':
        return img.ColorRgb8(255, 152, 0); // Orange (0xFFFF9800)
      case 'Incorrect_installation':
        return img.ColorRgb8(33, 150, 243); // Blue (0xFF2196F3)
      case 'PCB_damage':
        return img.ColorRgb8(156, 39, 176); // Purple (0xFF9C27B0)
      case 'Short_circuit':
        return img.ColorRgb8(244, 67, 54); // Red (0xFFF44336)
      default:
        return img.ColorRgb8(128, 128, 128); // Grey
    }
  }
  
  /// 앱과 동일한 라벨 위치 계산
  static ({double left, double top}) _getLabelPosition(String label, DetectedDefect defect, int defectNumber) {
    final bbox = defect.bbox;
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
  
  /// 사각형 그리기
  static void _drawRectangle(
    img.Image image,
    int x,
    int y,
    int width,
    int height,
    img.Color color,
    {int thickness = 3}
  ) {
    // 상단 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < width; j++) {
        if (x + j >= 0 && x + j < image.width && y + i >= 0 && y + i < image.height) {
          image.setPixel(x + j, y + i, color);
        }
      }
    }
    
    // 하단 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < width; j++) {
        if (x + j >= 0 && x + j < image.width && y + height - i >= 0 && y + height - i < image.height) {
          image.setPixel(x + j, y + height - i, color);
        }
      }
    }
    
    // 좌측 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < height; j++) {
        if (x + i >= 0 && x + i < image.width && y + j >= 0 && y + j < image.height) {
          image.setPixel(x + i, y + j, color);
        }
      }
    }
    
    // 우측 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < height; j++) {
        if (x + width - i >= 0 && x + width - i < image.width && y + j >= 0 && y + j < image.height) {
          image.setPixel(x + width - i, y + j, color);
        }
      }
    }
  }
  
  /// 텍스트 그리기 (앱과 동일한 형식 - 배경색 있는 라벨)
  static void _drawText(
    img.Image image,
    String text,
    int x,
    int y,
    img.Color color,
  ) {
    // 앱과 동일한 라벨 형식: 배경색이 있는 작은 박스
    final textWidth = text.length * 6 + 8; // 패딩 포함
    final textHeight = 16;
    
    // 라벨 배경 박스 (앱과 동일한 색상)
    for (int i = 0; i < textHeight; i++) {
      for (int j = 0; j < textWidth; j++) {
        if (x + j >= 0 && x + j < image.width && y + i >= 0 && y + i < image.height) {
          image.setPixel(x + j, y + i, color); // 배경색은 결함 색상과 동일
        }
      }
    }
    
    // 흰색 텍스트 그리기 (앱과 동일)
    for (int i = 4; i < textHeight - 4; i++) {
      for (int j = 4; j < textWidth - 4; j++) {
        if (x + j >= 0 && x + j < image.width && y + i >= 0 && y + i < image.height) {
          image.setPixel(x + j, y + i, img.ColorRgb8(255, 255, 255)); // 흰색 텍스트
        }
      }
    }
  }
}
