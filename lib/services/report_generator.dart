import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'detector.dart';

class ReportGenerator {
  Future<File> generateAndShare({required List<DetectedDefect> defects, String? advisorSummary}) async {
    final doc = pw.Document();

    final summary = _buildSummary(defects);
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text('PCB 진단 리포트', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('결과 요약: $summary'),
          pw.SizedBox(height: 12),
          if (advisorSummary != null) pw.Text('종합 의견 (AI 생성):\n$advisorSummary'),
          pw.SizedBox(height: 16),
          pw.Text('세부 내역'),
          pw.SizedBox(height: 8),
          ...defects.map((d) => pw.Bullet(text: '${d.label} (conf ${d.confidence.toStringAsFixed(2)}), box: [${d.bbox.left.toStringAsFixed(1)}, ${d.bbox.top.toStringAsFixed(1)}, ${d.bbox.width.toStringAsFixed(1)}, ${d.bbox.height.toStringAsFixed(1)}]')),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pcb_report.pdf');
    await file.writeAsBytes(await doc.save());
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: 'pcb_report.pdf');
    return file;
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

