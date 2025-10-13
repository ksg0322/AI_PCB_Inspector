import '../models/pcb_defect_models.dart';

class CapturedImage {
  final String imagePath;
  final List<DetectedDefect> defects;
  final DateTime timestamp;
  final String description;

  CapturedImage({
    required this.imagePath,
    required this.defects,
    required this.timestamp,
    required this.description,
  });
}
