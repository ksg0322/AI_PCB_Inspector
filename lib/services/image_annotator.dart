import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/pcb_defect_models.dart';
import '../utils/defect_overlay_util.dart';

class ImageAnnotator {
  /// 결함이 표시된 이미지를 생성
  static Future<String?> createAnnotatedImage({
    required String originalImagePath,
    required List<DetectedDefect> defects,
    required String outputPath,
  }) async {
    try {
      // silent

      // 원본 이미지 로드
      final originalFile = File(originalImagePath);
      if (!await originalFile.exists()) {
        // silent
        return null;
      }

      final imageBytes = await originalFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        // silent
        return null;
      }

      // silent

      // 결함 박스 그리기
      final annotatedImage = _drawDefectBoxes(originalImage, defects);

      // 주석이 달린 이미지 저장
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(annotatedImage));

      // silent
      return outputPath;
    } catch (e) {
      // silent
      return null;
    }
  }

  /// 결함 박스 그리기 (앱의 defect_overlays.dart 로직 활용)
  static img.Image _drawDefectBoxes(
    img.Image originalImage,
    List<DetectedDefect> defects,
  ) {
    final annotatedImage = img.Image.from(originalImage);

    // 앱과 동일한 카운터 로직
    final Map<String, int> counters = {};

    for (int i = 0; i < defects.length; i++) {
      final defect = defects[i];
      final bbox = defect.bbox;

      // 앱과 동일한 카운터 증가
      counters[defect.label] = (counters[defect.label] ?? 0) + 1;
      final defectNumber = counters[defect.label]!;

      // 박스 색상 결정 (앱과 동일)
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

      // 라벨 위치 계산 (앱과 동일한 로직)
      final labelPosition = DefectOverlayUtil.getLabelPosition(
        defect.label,
        defect.bbox,
      );

      // 라벨 그리기 (앱과 동일한 스타일)
      _drawLabel(
        annotatedImage,
        '$defectNumber',
        labelPosition.left.toInt(),
        labelPosition.top.toInt(),
        color,
      );
    }

    return annotatedImage;
  }

  /// 결함 종류별 색상 반환 (중앙 정의 색상 사용)
  static img.Color _getDefectColor(String label) {
    final rgb = DefectOverlayUtil.getRgb(label);
    return img.ColorRgb8(rgb.r, rgb.g, rgb.b);
  }

  // 라벨 위치 계산은 DefectOverlayUtil을 사용

  /// 사각형 그리기
  static void _drawRectangle(
    img.Image image,
    int x,
    int y,
    int width,
    int height,
    img.Color color, {
    int thickness = 3,
  }) {
    // 상단 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < width; j++) {
        if (x + j >= 0 &&
            x + j < image.width &&
            y + i >= 0 &&
            y + i < image.height) {
          image.setPixel(x + j, y + i, color);
        }
      }
    }

    // 하단 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < width; j++) {
        if (x + j >= 0 &&
            x + j < image.width &&
            y + height - i >= 0 &&
            y + height - i < image.height) {
          image.setPixel(x + j, y + height - i, color);
        }
      }
    }

    // 좌측 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < height; j++) {
        if (x + i >= 0 &&
            x + i < image.width &&
            y + j >= 0 &&
            y + j < image.height) {
          image.setPixel(x + i, y + j, color);
        }
      }
    }

    // 우측 선
    for (int i = 0; i < thickness; i++) {
      for (int j = 0; j < height; j++) {
        if (x + width - i >= 0 &&
            x + width - i < image.width &&
            y + j >= 0 &&
            y + j < image.height) {
          image.setPixel(x + width - i, y + j, color);
        }
      }
    }
  }

  /// 라벨 그리기 (앱과 동일한 스타일)
  static void _drawLabel(
    img.Image image,
    String text,
    int x,
    int y,
    img.Color color,
  ) {
    // 앱과 동일한 라벨 크기 (defect_overlays.dart 참조)
    final textWidth = text.length * 6 + 8; // 패딩 포함
    final textHeight = 16;

    // 라벨 배경 박스 (앱과 동일한 색상)
    for (int i = 0; i < textHeight; i++) {
      for (int j = 0; j < textWidth; j++) {
        if (x + j >= 0 &&
            x + j < image.width &&
            y + i >= 0 &&
            y + i < image.height) {
          image.setPixel(x + j, y + i, color); // 배경색은 결함 색상과 동일
        }
      }
    }

    // 숫자 텍스트 그리기 (간단한 픽셀 패턴)
    _drawNumber(image, text, x + 4, y + 3, img.ColorRgb8(255, 255, 255));
  }

  /// 숫자 그리기 (간단한 픽셀 패턴)
  static void _drawNumber(
    img.Image image,
    String number,
    int x,
    int y,
    img.Color color,
  ) {
    final digitWidth = 6;
    final digitHeight = 10;

    for (int i = 0; i < number.length; i++) {
      final digit = number[i];
      final digitX = x + (i * digitWidth);
      final digitY = y;

      _drawDigit(image, digit, digitX, digitY, color, digitWidth, digitHeight);
    }
  }

  /// 개별 숫자 그리기
  static void _drawDigit(
    img.Image image,
    String digit,
    int x,
    int y,
    img.Color color,
    int width,
    int height,
  ) {
    // 간단한 7-세그먼트 스타일 숫자 그리기
    switch (digit) {
      case '1':
        _drawVerticalLine(image, x + width - 2, y, height, color);
        break;
      case '2':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x + width - 1, y, height ~/ 2, color);
        _drawVerticalLine(image, x, y + height ~/ 2, height ~/ 2, color);
        break;
      case '3':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
      case '4':
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawVerticalLine(image, x, y, height ~/ 2, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
      case '5':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x, y, height ~/ 2, color);
        _drawVerticalLine(
          image,
          x + width - 1,
          y + height ~/ 2,
          height ~/ 2,
          color,
        );
        break;
      case '6':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x, y, height, color);
        _drawVerticalLine(
          image,
          x + width - 1,
          y + height ~/ 2,
          height ~/ 2,
          color,
        );
        break;
      case '7':
        _drawHorizontalLine(image, x, y, width, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
      case '8':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x, y, height, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
      case '9':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height ~/ 2, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x, y, height ~/ 2, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
      case '0':
        _drawHorizontalLine(image, x, y, width, color);
        _drawHorizontalLine(image, x, y + height - 1, width, color);
        _drawVerticalLine(image, x, y, height, color);
        _drawVerticalLine(image, x + width - 1, y, height, color);
        break;
    }
  }

  /// 수평선 그리기
  static void _drawHorizontalLine(
    img.Image image,
    int x,
    int y,
    int width,
    img.Color color,
  ) {
    for (int i = 0; i < width; i++) {
      if (x + i >= 0 && x + i < image.width && y >= 0 && y < image.height) {
        image.setPixel(x + i, y, color);
      }
    }
  }

  /// 수직선 그리기
  static void _drawVerticalLine(
    img.Image image,
    int x,
    int y,
    int height,
    img.Color color,
  ) {
    for (int i = 0; i < height; i++) {
      if (x >= 0 && x < image.width && y + i >= 0 && y + i < image.height) {
        image.setPixel(x, y + i, color);
      }
    }
  }
}
