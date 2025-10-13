import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraControllerHelper {
  static Future<CameraController?> initializeBackCamera({
    required List<CameraDescription> cameras,
    ResolutionPreset preset = ResolutionPreset.medium,
  }) async {
    if (cameras.isEmpty) return null;
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(back, preset, enableAudio: false);
    await controller.initialize();
    return controller;
  }

  static Future<void> disposeController(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } catch (e) {
      debugPrint('Camera dispose error: $e');
    }
  }
}
