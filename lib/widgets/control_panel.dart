import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  final bool isGalleryMode;
  final bool isCameraInitialized;
  final bool isDetecting;
  final int capturedImagesCount;
  final bool hasImage;
  final VoidCallback onStartDetectOrCapture;
  final VoidCallback onClearImage;
  final VoidCallback onAskAi;
  final VoidCallback onMakeReport;

  const ControlPanel({
    super.key,
    required this.isGalleryMode,
    required this.isCameraInitialized,
    required this.isDetecting,
    required this.capturedImagesCount,
    required this.hasImage,
    required this.onStartDetectOrCapture,
    required this.onClearImage,
    required this.onAskAi,
    required this.onMakeReport,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AI 문의와 리포트 버튼
          if (hasImage) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAskAi,
                    icon: const Icon(Icons.chat, size: 16),
                    label: const Text('AI 문의', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onMakeReport,
                    icon: const Icon(Icons.description, size: 16),
                    label: Text(
                      '리포트${capturedImagesCount > 0 ? ' ($capturedImagesCount)' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // 메인 탐지 버튼
          SizedBox(
            width: screenWidth * 0.8,
            child: ElevatedButton.icon(
              onPressed: onStartDetectOrCapture,
              icon: Icon(
                isDetecting ? Icons.camera : Icons.play_arrow,
                size: 20,
              ),
              label: Text(
                isDetecting ? '사진 촬영' : '탐지',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDetecting ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
