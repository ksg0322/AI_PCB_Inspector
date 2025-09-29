import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  final bool isGalleryMode;
  final bool isCameraInitialized;
  final bool isDetecting;
  final int capturedImagesCount;
  final bool hasImage;
  final VoidCallback onStartDetectOrCapture;
  final VoidCallback onPickImage;
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
    required this.onPickImage,
    required this.onClearImage,
    required this.onAskAi,
    required this.onMakeReport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isGalleryMode || isCameraInitialized) ...[
          if (isGalleryMode) ...[
            ElevatedButton.icon(
              onPressed: onPickImage,
              icon: const Icon(Icons.photo_library, size: 20),
              label: const Text('다른 이미지 선택', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: onStartDetectOrCapture,
              icon: Icon(isDetecting ? Icons.camera : Icons.play_arrow, size: 20),
              label: Text(isDetecting ? '사진 촬영' : '탐지 시작', style: const TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDetecting ? Colors.orange : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (isGalleryMode)
                ElevatedButton.icon(
                  onPressed: onClearImage,
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('카메라로 전환', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: onPickImage,
                  icon: const Icon(Icons.photo_library, size: 16),
                  label: const Text('갤러리', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              if (hasImage)
                ElevatedButton.icon(
                  onPressed: onClearImage,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('이미지 해제', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
        ] else ...[
          ElevatedButton.icon(
            onPressed: onStartDetectOrCapture,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('탐지 시작', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: onPickImage,
            icon: const Icon(Icons.photo_library, size: 16),
            label: const Text('갤러리', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
        
        // AI 문의와 리포트 버튼은 이미지가 있을 때 항상 표시 (카메라 상태와 무관)
        if (hasImage) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: onAskAi,
                icon: const Icon(Icons.chat, size: 16),
                label: const Text('AI 문의', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              ElevatedButton.icon(
                onPressed: onMakeReport,
                icon: const Icon(Icons.description, size: 16),
                label: Text('리포트 생성${capturedImagesCount > 0 ? ' ($capturedImagesCount)' : ''}', style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
