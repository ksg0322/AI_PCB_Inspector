import 'package:flutter/material.dart';

class DefectSummaryPanel extends StatelessWidget {
  final int totalCount;
  final List<Widget> summaryChips;
  final List<Widget> detailChips;
  final VoidCallback? onGenerateReport;
  final VoidCallback? onAskAi;

  const DefectSummaryPanel({
    super.key,
    required this.totalCount,
    required this.summaryChips,
    required this.detailChips,
    this.onGenerateReport,
    this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '탐지된 결함:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Row(
                children: [
                  if (onAskAi != null)
                    ElevatedButton.icon(
                      onPressed: onAskAi,
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text(
                        'AI 문의',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  if (onAskAi != null && onGenerateReport != null)
                    const SizedBox(width: 8),
                  if (onGenerateReport != null)
                    ElevatedButton(
                      onPressed: onGenerateReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '리포트 생성',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (summaryChips.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 6, children: summaryChips),
            const SizedBox(height: 10),
          ],
          const Text(
            '상세 정보:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: detailChips),
        ],
      ),
    );
  }
}
