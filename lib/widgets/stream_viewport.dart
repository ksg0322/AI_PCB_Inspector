import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/pcb_defect_models.dart';
import 'defect_overlays.dart';

class StreamViewport extends StatelessWidget {
  final CameraController? camera;
  final bool isCameraInitialized;
  final XFile? galleryImage;
  final XFile? capturedImage;
  final List<DetectedDefect> latestDefects;
  final double? maxHeight;

  const StreamViewport({
    super.key,
    required this.camera,
    required this.isCameraInitialized,
    required this.galleryImage,
    required this.capturedImage,
    required this.latestDefects,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewW = constraints.maxWidth;

        // maxHeight가 제공되면 사용, 아니면 안전한 폴백 값 사용
        final double viewH =
            maxHeight ??
            (constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height * 0.5);

        Widget imageWidget;
        int srcW;
        int srcH;
        if (galleryImage != null) {
          imageWidget = Image.file(
            File(galleryImage!.path),
            fit: BoxFit.contain,
          );
          srcW = latestDefects.isNotEmpty
              ? latestDefects.first.sourceWidth
              : viewW.toInt();
          srcH = latestDefects.isNotEmpty
              ? latestDefects.first.sourceHeight
              : viewW.toInt(); // viewH 대신 viewW 사용 (안전)
        } else if (capturedImage != null) {
          imageWidget = Image.file(
            File(capturedImage!.path),
            fit: BoxFit.contain,
          );
          srcW = latestDefects.isNotEmpty
              ? latestDefects.first.sourceWidth
              : viewW.toInt();
          srcH = latestDefects.isNotEmpty
              ? latestDefects.first.sourceHeight
              : viewW.toInt(); // viewH 대신 viewW 사용 (안전)
        } else if (isCameraInitialized && camera != null) {
          imageWidget = CameraPreview(camera!);

          // 카메라 모드에서도 탐지 결과의 sourceWidth/Height를 우선 사용 (좌표 기준 통일)
          if (latestDefects.isNotEmpty) {
            srcW = latestDefects.first.sourceWidth;
            srcH = latestDefects.first.sourceHeight;
          } else {
            // 탐지 결과가 없을 때만 previewSize 사용
            final s = camera!.value.previewSize;
            final orientation = MediaQuery.of(context).orientation;
            if (s != null) {
              srcW = orientation == Orientation.landscape
                  ? s.width.toInt()
                  : s.height.toInt();
              srcH = orientation == Orientation.landscape
                  ? s.height.toInt()
                  : s.width.toInt();
            } else {
              srcW = viewW.toInt();
              srcH = viewW.toInt(); // viewH 대신 viewW 사용 (안전)
            }
          }
        } else {
          imageWidget = Container(
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.photo_camera, size: 72, color: Colors.black38),
            ),
          );
          srcW = viewW.toInt();
          srcH = viewW.toInt(); // viewH 대신 viewW 사용 (안전)
        }

        final double imageAspectRatio = srcW / srcH;
        final double viewAspectRatio = viewW / viewH;

        double actualImageWidth, actualImageHeight;
        double offsetX, offsetY;

        // 갤러리 이미지나 촬영된 이미지일 때 - 여백 완전 제거
        if (galleryImage != null || capturedImage != null) {
          // 가로 기준으로 이미지 크기 계산
          actualImageWidth = viewW;
          actualImageHeight = viewW / imageAspectRatio;

          // maxHeight 제한 적용 (오버플로우 방지)
          if (actualImageHeight > viewH) {
            actualImageHeight = viewH;
            actualImageWidth = viewH * imageAspectRatio;
          }

          offsetX = 0;
          offsetY = 0;

          // 정확한 크기의 SizedBox 반환 → 여백 없음
          return SizedBox(
            width: actualImageWidth,
            height: actualImageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: srcW.toDouble(),
                    height: srcH.toDouble(),
                    child: imageWidget,
                  ),
                ),
                if (latestDefects.isNotEmpty)
                  DefectOverlays(
                    defects: latestDefects,
                    offsetX: 0,
                    offsetY: 0,
                    actualImageWidth: actualImageWidth,
                    actualImageHeight: actualImageHeight,
                  ),
              ],
            ),
          );
        }

        // 카메라 프리뷰 모드 - 고정 높이 영역 사용
        if (imageAspectRatio > viewAspectRatio) {
          actualImageWidth = viewW;
          actualImageHeight = viewW / imageAspectRatio;
          offsetX = 0;
          offsetY = (viewH - actualImageHeight) / 2;
        } else {
          actualImageHeight = viewH;
          actualImageWidth = viewH * imageAspectRatio;
          offsetX = (viewW - actualImageWidth) / 2;
          offsetY = 0;
        }

        return SizedBox(
          height: viewH, // 카메라 모드는 고정 높이
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: SizedBox(
                  width: srcW.toDouble(),
                  height: srcH.toDouble(),
                  child: imageWidget,
                ),
              ),
              if (latestDefects.isNotEmpty)
                DefectOverlays(
                  defects: latestDefects,
                  offsetX: offsetX,
                  offsetY: offsetY,
                  actualImageWidth: actualImageWidth,
                  actualImageHeight: actualImageHeight,
                ),
            ],
          ),
        );
      },
    );
  }
}
