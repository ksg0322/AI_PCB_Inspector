import 'package:camera/camera.dart';
import '../models/captured_image.dart';
import '../models/pcb_defect_models.dart';
import 'camera_controller_helper.dart';
import 'defect_summary_util.dart';
import 'detector_service.dart';

class DetectPageController {
  final DetectorService detector;
  DetectPageController(this.detector);

  Future<CameraController?> initCamera(List<CameraDescription> cameras) async {
    return CameraControllerHelper.initializeBackCamera(cameras: cameras);
  }

  Future<void> stopStreaming(CameraController? camera) async {
    if (camera == null) return;
    if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
  }

  Future<void> disposeCamera(CameraController? camera) async {
    await CameraControllerHelper.disposeController(camera);
  }

  Future<List<DetectedDefect>> detectOnFrame(CameraImage image) async {
    return detector.detectOnFrame(cameraImage: image);
  }

  Future<List<DetectedDefect>> detectOnImagePath(String path) async {
    return detector.detectOnImagePath(path);
  }

  String buildDefectDescription(List<DetectedDefect> defects) {
    return DefectSummaryUtil.generateDescription(defects);
  }

  Future<CapturedImage> buildCaptured(String imagePath, List<DetectedDefect> defects) async {
    final description = buildDefectDescription(defects);
    return CapturedImage(
      imagePath: imagePath,
      defects: defects,
      timestamp: DateTime.now(),
      description: description,
    );
  }
}


