import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/pcb_defect_models.dart';
import '../models/captured_image.dart';
import 'image_annotator.dart';

class ReportGenerator {
  Future<File> generateAndShare({
    required List<DetectedDefect> defects,
    String? advisorSummary,
    List<CapturedImage>? capturedImages,
  }) async {
    final doc = pw.Document();

    // 한글 지원 폰트 로드
    final notoSansFont = await _loadKoreanFont();

    // 한글 지원 폰트 스타일 정의
    final notoSansBold = pw.TextStyle(
      font: notoSansFont,
      fontWeight: pw.FontWeight.bold,
    );
    final notoSansNormal = pw.TextStyle(font: notoSansFont);
    final notoSansLarge = pw.TextStyle(
      font: notoSansFont,
      fontSize: 24,
      fontWeight: pw.FontWeight.bold,
    );
    final notoSansMedium = pw.TextStyle(
      font: notoSansFont,
      fontSize: 20,
      fontWeight: pw.FontWeight.bold,
    );

    // 현재 시간
    final now = DateTime.now();
    final reportTime =
        '${now.year}년 ${now.month}월 ${now.day}일 ${now.hour}시 ${now.minute}분';

    // 첫 번째 페이지: 리포트 헤더와 시간
    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(' $reportTime', style: notoSansNormal),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('PCB 진단 리포트', style: notoSansLarge),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Text('검사 결과 요약', style: notoSansMedium),
              pw.SizedBox(height: 10),
              pw.Text(_buildSummary(defects), style: notoSansNormal),
              pw.SizedBox(height: 16),
              if (advisorSummary != null) ...[
                pw.Text('AI 종합 의견', style: notoSansMedium),
                pw.SizedBox(height: 10),
                pw.Text(advisorSummary, style: notoSansNormal),
                pw.SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );

    // 촬영한 이미지가 있으면 이미지 페이지들을 먼저 추가
    if (capturedImages != null && capturedImages.isNotEmpty) {
      for (int i = 0; i < capturedImages.length; i++) {
        await _addImagePage(
          doc,
          capturedImages[i],
          i + 1,
          notoSansBold,
          notoSansNormal,
          notoSansMedium,
        );
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pcb_report.pdf');
    await file.writeAsBytes(await doc.save());
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: 'pcb_report.pdf',
    );
    return file;
  }

  /// 이미지 페이지를 PDF에 추가
  Future<void> _addImagePage(
    pw.Document doc,
    CapturedImage capturedImage,
    int imageNumber,
    pw.TextStyle notoSansBold,
    pw.TextStyle notoSansNormal,
    pw.TextStyle notoSansMedium,
  ) async {
    try {
      // 결함이 표시된 이미지 생성
      final tempDir = await getTemporaryDirectory();
      final annotatedImagePath =
          '${tempDir.path}/annotated_image_$imageNumber.jpg';

      final annotatedPath = await ImageAnnotator.createAnnotatedImage(
        originalImagePath: capturedImage.imagePath,
        defects: capturedImage.defects,
        outputPath: annotatedImagePath,
      );

      // 주석이 달린 이미지가 생성되었으면 사용, 아니면 원본 사용
      final imagePath = annotatedPath ?? capturedImage.imagePath;
      final imageFile = File(imagePath);

      if (!await imageFile.exists()) {
        return;
      }

      final imageBytes = await imageFile.readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      // 이미지 페이지 추가
      doc.addPage(
        pw.Page(
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('이미지 #$imageNumber', style: notoSansMedium),
                pw.SizedBox(height: 8),
                pw.Text(
                  '파일명: ${imageFile.path.split('/').last}',
                  style: notoSansNormal,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '탐지된 결함: ${capturedImage.defects.length}개',
                  style: notoSansNormal,
                ),
                pw.SizedBox(height: 16),
                // 이미지 표시 (크기 조정)
                pw.Center(
                  child: pw.Container(
                    constraints: const pw.BoxConstraints(
                      maxWidth: 500,
                      maxHeight: 400,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Image(image, fit: pw.BoxFit.contain),
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),
                // 결함 목록
                if (capturedImage.defects.isNotEmpty) ...[
                  pw.Text('이 이미지에서 탐지된 결함:', style: notoSansMedium),
                  pw.SizedBox(height: 8),
                  ...capturedImage.defects.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final defect = entry.value;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          children: [
                            pw.Text('$index. ', style: notoSansBold),
                            pw.Text('${defect.label} ', style: notoSansNormal),
                            pw.Text(
                              '(신뢰도: ${(defect.confidence * 100).toInt()}%)',
                              style: notoSansNormal,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ] else ...[
                  pw.Text('이 이미지에서는 결함이 탐지되지 않았습니다.', style: notoSansNormal),
                ],
              ],
            );
          },
        ),
      );
    } catch (e) {
      // silent
    }
  }

  /// 한글 지원 폰트 로드
  Future<pw.Font> _loadKoreanFont() async {
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoSansKR-Regular.ttf',
      );
      return pw.Font.ttf(fontData);
    } catch (e) {
      return pw.Font.helvetica();
    }
  }

  String _buildSummary(List<DetectedDefect> defects) {
    if (defects.isEmpty) return '불량이 감지되지 않았습니다.';
    final counts = <String, int>{};
    for (final d in defects) {
      counts[d.label] = (counts[d.label] ?? 0) + 1;
    }
    final total = defects.length;
    final details = counts.entries
        .map((e) => '${e.key} ${e.value}건')
        .join(', ');
    return '총 ${total}건: $details';
  }
}
