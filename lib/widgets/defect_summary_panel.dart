import 'package:flutter/material.dart';

class DefectSummaryPanel extends StatelessWidget {
  final int totalCount;
  final List<Widget> summaryChips;
  final List<Widget> detailChips;

  const DefectSummaryPanel({
    super.key,
    required this.totalCount,
    required this.summaryChips,
    required this.detailChips,
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
            children: [
              const Text(
                '탐지된 결함:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (summaryChips.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: summaryChips,
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            '상세 정보:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: detailChips,
          ),
        ],
      ),
    );
  }
}
