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
    print('📄 리포트 생성 시작 - 한글 폰트 로드 중...');
    final koreanFont = await _loadKoreanFont();
    print('📄 한글 폰트 로드 완료');
    
    // 한글 지원 폰트 스타일 정의
    final arialBold = pw.TextStyle(font: koreanFont, fontWeight: pw.FontWeight.bold);
    final arialNormal = pw.TextStyle(font: koreanFont);
    final arialLarge = pw.TextStyle(font: koreanFont, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final arialMedium = pw.TextStyle(font: koreanFont, fontSize: 14, fontWeight: pw.FontWeight.bold);

    // 현재 시간
    final now = DateTime.now();
    final reportTime = '${now.year}년 ${now.month}월 ${now.day}일 ${now.hour}시 ${now.minute}분';

    // 첫 번째 페이지: 리포트 헤더와 시간
    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PCB 진단 리포트', style: arialLarge),
              pw.SizedBox(height: 16),
              pw.Text('리포트 생성 시간: $reportTime', style: arialNormal),
              pw.SizedBox(height: 20),
              pw.Text('검사 결과 요약', style: arialMedium),
              pw.SizedBox(height: 8),
              pw.Text(_buildSummary(defects), style: arialNormal),
              pw.SizedBox(height: 16),
              if (advisorSummary != null) ...[
                pw.Text('AI 종합 의견', style: arialMedium),
                pw.SizedBox(height: 8),
                pw.Text(advisorSummary, style: arialNormal),
                pw.SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );

    // 촬영한 이미지가 있으면 이미지 페이지들을 먼저 추가
    if (capturedImages != null && capturedImages.isNotEmpty) {
      for (int i = 0; i < capturedImages.length; i++) {
        await _addImagePage(doc, capturedImages[i], i + 1, arialBold, arialNormal, arialMedium);
      }
    }


    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pcb_report.pdf');
    await file.writeAsBytes(await doc.save());
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: 'pcb_report.pdf');
    return file;
  }

  /// 이미지 페이지를 PDF에 추가
  Future<void> _addImagePage(
    pw.Document doc, 
    CapturedImage capturedImage, 
    int imageNumber,
    pw.TextStyle arialBold,
    pw.TextStyle arialNormal,
    pw.TextStyle arialMedium,
  ) async {
    try {
      // 결함이 표시된 이미지 생성
      final tempDir = await getTemporaryDirectory();
      final annotatedImagePath = '${tempDir.path}/annotated_image_$imageNumber.jpg';
      
      print('🖼️ 결함 주석 이미지 생성 중: $annotatedImagePath');
      final annotatedPath = await ImageAnnotator.createAnnotatedImage(
        originalImagePath: capturedImage.imagePath,
        defects: capturedImage.defects,
        outputPath: annotatedImagePath,
      );
      
      // 주석이 달린 이미지가 생성되었으면 사용, 아니면 원본 사용
      final imagePath = annotatedPath ?? capturedImage.imagePath;
      final imageFile = File(imagePath);
      
      if (!await imageFile.exists()) {
        print('⚠️ 이미지 파일이 존재하지 않습니다: $imagePath');
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
                pw.Text(
                  '촬영 이미지 #$imageNumber',
                  style: arialMedium,
                ),
                pw.SizedBox(height: 8),
                pw.Text('파일명: ${imageFile.path.split('/').last}', style: arialNormal),
                pw.SizedBox(height: 8),
                pw.Text('탐지된 결함: ${capturedImage.defects.length}개', style: arialNormal),
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
                      child: pw.Image(
                        image,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),
                // 결함 목록
                if (capturedImage.defects.isNotEmpty) ...[
                  pw.Text(
                    '이 이미지에서 탐지된 결함:',
                    style: arialMedium,
                  ),
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
                            pw.Text('$index. ', style: arialBold),
                            pw.Text('${defect.label} ', style: arialNormal),
                            pw.Text('(신뢰도: ${(defect.confidence * 100).toInt()}%)', style: arialNormal),
                          ],
                        ),
                      ),
                    );
                  }),
                ] else ...[
                  pw.Text(
                    '이 이미지에서는 결함이 탐지되지 않았습니다.',
                    style: arialNormal,
                  ),
                ],
              ],
            );
          },
        ),
      );
    } catch (e) {
      print('❌ 이미지 페이지 추가 실패: $e');
    }
  }


  /// 한글 지원 폰트 로드
  Future<pw.Font> _loadKoreanFont() async {
    try {
      print('🔤 한글 폰트 로드 시도: assets/fonts/NotoSansKR-Regular.ttf');
      // 먼저 assets에서 한글 폰트 시도
      final fontData = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
      print('✅ 한글 폰트 로드 성공: ${fontData.lengthInBytes} bytes');
      return pw.Font.ttf(fontData);
    } catch (e) {
      print('⚠️ 한글 폰트 로드 실패, 기본 폰트 사용: $e');
      // 폰트 로드 실패 시 기본 폰트 사용
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
    final details = counts.entries.map((e) => '${e.key} ${e.value}건').join(', ');
    return '총 ${total}건: $details';
  }
}

