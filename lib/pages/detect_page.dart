import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/detector_service.dart';
import '../models/pcb_defect_models.dart';
import '../utils/defect_overlay_util.dart';
import '../services/ai_advisor.dart';
import '../services/report_generator.dart';
import '../models/captured_image.dart';
import '../services/detect_page_controller.dart';
import '../services/photo_saver.dart';
import '../widgets/stream_viewport.dart';
import '../widgets/defect_summary_panel.dart';
import '../widgets/ai_response_panel.dart';
import '../widgets/thumbnail_strip.dart';

class DetectPage extends StatefulWidget {
  const DetectPage({super.key});

  @override
  State<DetectPage> createState() => _DetectPageState();
}

class _DetectPageState extends State<DetectPage> with WidgetsBindingObserver {
  final DetectorService _detector = DetectorService();
  late final DetectPageController _pageController;
  final AiAdvisorService _advisor = AiAdvisorService();
  final ReportGenerator _report = ReportGenerator();
  final GlobalKey<ThumbnailStripState> _thumbnailStripKey =
      GlobalKey<ThumbnailStripState>();

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];

  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  List<DetectedDefect> _latest = const [];
  String? _advisorText;
  bool _isInitializingCamera = false;

  bool _inferenceBusy = false;
  int _lastInferMs = 0;
  static const int _minIntervalMs = 150; // CPU 멀티스레드 최적화 (약 6-7 FPS)

  XFile? _galleryImage;
  XFile? _capturedImage;
  List<CapturedImage> _capturedImages = [];
  List<XFile> _recentImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = DetectPageController(_detector);
    _initialize();
  }

  void debugLog(Object? message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      await _detector.initialize();
      setState(() {});
    } catch (e) {
      debugLog('초기화 오류: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitialized || _isInitializingCamera) return;

    if (_cameras.isEmpty) {
      try {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) {
          debugLog('사용 가능한 카메라가 없습니다.');
          return;
        }
      } catch (e) {
        debugLog('카메라 목록 가져오기 실패: $e');
        return;
      }
    }

    try {
      _isInitializingCamera = true;
      setState(() {}); // 초기화 시작 상태 업데이트

      _camera = await _pageController.initCamera(_cameras);
      if (_camera == null) {
        throw Exception('카메라 컨트롤러 생성 실패');
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isInitializingCamera = false;
        });
      }
    } catch (e) {
      debugLog('카메라 초기화 오류: $e');
      if (mounted) {
        setState(() {
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<void> _disposeCamera() async {
    if (_camera == null) return;

    // 먼저 탐지 중지
    await _stopDetect();

    try {
      // 카메라 컨트롤러 안전하게 해제
      if (_camera!.value.isInitialized) {
        await _pageController.disposeCamera(_camera);
      }
    } catch (e) {
      debugLog('⚠️ 카메라 dispose 오류: $e');
    } finally {
      _camera = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _isDetecting = false;
        });
      } else {
        _isCameraInitialized = false;
        _isDetecting = false;
      }
    }
  }

  Future<void> _startDetectAndCamera() async {
    if (_isDetecting) return;
    
    setState(() {
      _galleryImage = null;
      _capturedImage = null;
      _latest = [];
    });
    
    if (!_isCameraInitialized) {
      await _initializeCamera();
      if (!_isCameraInitialized) return;
    }
    
    await _startDetect();
  }

  Future<void> _captureAndStop() async {
    if (!_isDetecting) return;
    await _capturePhoto();
    await _stopDetect();
  }

  Future<void> _startDetect() async {
    if (_camera == null || !_isCameraInitialized || _isDetecting) return;

    setState(() => _isDetecting = true);
    _inferenceBusy = false;
    _lastInferMs = 0;
    _startPreviewDetection();
  }

  void _startPreviewDetection() {
    if (!_isDetecting) return;

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (!_isDetecting || _camera == null || !_isCameraInitialized) return;
      if (!_camera!.value.isInitialized) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (_inferenceBusy || now - _lastInferMs < _minIntervalMs) {
        _startPreviewDetection();
        return;
      }

      _inferenceBusy = true;
      _lastInferMs = now;

      try {
        final image = await _camera!.takePicture();
        final results = await _pageController.detectOnImagePath(image.path);

        if (mounted && _isDetecting) {
          setState(() => _latest = results);
        }

        try {
          await File(image.path).delete();
        } catch (e) {
          // Ignore file deletion errors
        }
      } catch (e) {
        debugLog('탐지 오류: $e');
        if (e.toString().contains('Disposed CameraController') ||
            e.toString().contains('CameraException')) {
          debugLog('❌ 카메라 오류로 인한 탐지 중지');
          await _stopDetect();
        }
      } finally {
        _inferenceBusy = false;
        if (_isDetecting) _startPreviewDetection();
      }
    });
  }

  Future<void> _stopDetect() async {
    if (!_isDetecting) return;

    setState(() => _isDetecting = false);
    _inferenceBusy = false;

    if (_camera != null && _isCameraInitialized) {
      try {
        if (_camera!.value.isStreamingImages) {
          await _camera!.stopImageStream();
        }
      } catch (e) {
        debugLog('⚠️ 카메라 스트림 중지 오류: $e');
      }
    }
  }

  Future<void> _askAi() async {
    try {
      final validDefects = _latest;
      if (validDefects.isEmpty) {
        setState(() => _advisorText = '탐지된 불량이 없습니다.');
        return;
      }

      // 탐지된 모든 불량의 라벨을 수집
      final defectLabels = validDefects.map((defect) => defect.label).toSet().toList();
      
      String text;
      if (defectLabels.length == 1) {
        // 단일 불량인 경우 기존 방식 사용
        text = await _advisor.askAdvisor(defectLabel: defectLabels.first);
      } else {
        // 여러 불량인 경우 새로운 방식 사용
        text = await _advisor.askAdvisorForMultipleDefects(defectLabels: defectLabels);
      }

      setState(() => _advisorText = text);
    } catch (e) {
      debugLog('❌ AI 문의 오류: $e');
      setState(() => _advisorText = 'AI 응답을 가져오는 중 오류가 발생했습니다: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_camera == null || !_isCameraInitialized) return;

    if (_galleryImage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('갤러리 이미지가 선택되었습니다. 먼저 이미지를 해제해주세요.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final image = await _camera!.takePicture();

      if (_isDetecting) await _stopDetect();
      if (_isCameraInitialized) await _disposeCamera();

      await Future.delayed(const Duration(milliseconds: 300));
      final capturedDefects = await _pageController.detectOnImagePath(image.path);
      final savedPath = await PhotoSaver.savePhotoToGallery(image);
      final capturedImage = await _pageController.buildCaptured(image.path, capturedDefects);

      setState(() {
        _capturedImages.add(capturedImage);
        _capturedImage = image;
        _latest = capturedDefects;
        _isDetecting = false;

        _recentImages.insert(0, image);
        if (_recentImages.length > 5) {
          _recentImages.removeLast();
        }
      });

      if (mounted) {
        final saveStatus = savedPath != null ? '저장되었습니다' : '저장에 실패했습니다';
        final message = '사진이 $saveStatus. ${capturedDefects.length}개의 결함이 탐지되었습니다.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: savedPath != null ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugLog('Photo capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('사진 촬영에 실패했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleImageSelected(XFile image) async {
    if (_isDetecting) await _stopDetect();
    if (_isCameraInitialized) await _disposeCamera();

    setState(() {
      _galleryImage = image;
      _capturedImage = image;
    });

    final results = await _pageController.detectOnImagePath(image.path);

    setState(() {
      _latest = results;

      if (!_recentImages.any((img) => img.path == image.path)) {
        _recentImages.insert(0, image);
        if (_recentImages.length > 5) {
          _recentImages.removeLast();
        }
      }
    });

    if (results.isNotEmpty) {
      final description = _pageController.buildDefectDescription(results);
      final capturedImage = CapturedImage(
        imagePath: image.path,
        defects: List.from(results),
        timestamp: DateTime.now(),
        description: description,
      );

      setState(() {
        _capturedImages.add(capturedImage);
      });
    }
  }

  Future<void> _handleImageDeleted(XFile image) async {
    setState(() {
      _recentImages.removeWhere((img) => img.path == image.path);
      _capturedImages.removeWhere((captured) => captured.imagePath == image.path);
      
      if (_galleryImage?.path == image.path || _capturedImage?.path == image.path) {
        _galleryImage = null;
        _capturedImage = null;
        _latest = [];
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('썸네일 이미지가 삭제되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _makeReportFromSelectedThumbnails(
    Set<String> selectedPaths,
  ) async {
    if (selectedPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('리포트를 생성하려면 먼저 이미지를 선택해주세요. (길게 눌러서 선택)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 선택된 이미지들의 탐지 결과 찾기
    final selectedCapturedImages = _capturedImages
        .where((captured) => selectedPaths.contains(captured.imagePath))
        .toList();

    if (selectedCapturedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('선택된 이미지의 탐지 결과를 찾을 수 없습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 선택된 이미지들의 결함들을 수집
    final selectedDefects = <DetectedDefect>[];
    for (final capturedImage in selectedCapturedImages) {
      selectedDefects.addAll(capturedImage.defects);
    }

    // 리포트 생성
    await _report.generateAndShare(
      defects: selectedDefects,
      advisorSummary: _advisorText,
      capturedImages: selectedCapturedImages,
    );

    // 리포트 생성 후 선택 해제
    _thumbnailStripKey.currentState?.clearSelection();
  }

  Future<void> _makeReportFromSelectedOrAll() async {
    // 썸네일에서 선택된 이미지가 있는지 확인
    final selectedPaths = _thumbnailStripKey.currentState?.selectedImagePaths;

    if (selectedPaths != null && selectedPaths.isNotEmpty) {
      // 선택된 이미지가 있으면 선택된 것만 리포트 생성
      await _makeReportFromSelectedThumbnails(selectedPaths);
    } else {
      // 선택된 이미지가 없으면 이미지 선택 알림 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('리포트를 생성하려면 먼저 이미지를 선택해주세요. (길게 눌러서 선택)'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Color _getDefectColor(String label) =>
      DefectOverlayUtil.getFlutterColor(label);

  List<Widget> _buildDefectChips() {
    if (_latest.isEmpty) return [];

    final Map<String, int> defectCounters = {};
    final List<Widget> chips = [];

    for (final defect in _latest) {
      defectCounters[defect.label] = (defectCounters[defect.label] ?? 0) + 1;
      final defectNumber = defectCounters[defect.label]!;

      chips.add(
        Chip(
          label: Text(
            '${defect.label} #$defectNumber (${(defect.confidence * 100).toInt()}%)',
            style: const TextStyle(fontSize: 13),
          ),
          backgroundColor: _getDefectColor(defect.label).withOpacity(0.3),
          labelStyle: TextStyle(color: _getDefectColor(defect.label)),
        ),
      );
    }

    return chips;
  }

  List<Widget> _buildDefectSummaryChips() {
    if (_latest.isEmpty) return [];

    final Map<String, int> defectCounts = {};
    for (final defect in _latest) {
      defectCounts[defect.label] = (defectCounts[defect.label] ?? 0) + 1;
    }

    final List<Widget> summaryChips = [];
    defectCounts.forEach((label, count) {
      summaryChips.add(
        Chip(
          label: Text(
            '$label: $count개',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          backgroundColor: _getDefectColor(label).withOpacity(0.2),
          labelStyle: TextStyle(color: _getDefectColor(label)),
          side: BorderSide(color: _getDefectColor(label), width: 1),
        ),
      );
    });

    return summaryChips;
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);

      // 탐지 중지
      _isDetecting = false;
      _inferenceBusy = false;

      // 카메라 안전하게 해제
      if (_camera != null) {
        try {
          if (_camera!.value.isInitialized) {
            _camera!.dispose();
          }
        } catch (e) {
          debugLog('⚠️ 카메라 dispose 오류: $e');
        }
        _camera = null;
      }

      // 탐지 서비스 해제
      _detector.dispose();
    } catch (e) {
      debugLog('⚠️ dispose 오류: $e');
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 페이지가 비가시/중지되면 스트림 중단 및 카메라 해제
        if (_camera != null && _camera!.value.isInitialized) {
          _disposeCamera();
        }
        break;
      case AppLifecycleState.resumed:
        // 자동 재초기화 금지: 사용자가 '탐지 시작'을 눌러야 카메라를 켬
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeHeight = MediaQuery.of(context).padding.top + MediaQuery.of(context).padding.bottom;
    final maxImageHeight = (screenHeight - safeHeight) * 0.5;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StreamViewport(
              camera: _camera,
              isCameraInitialized: _isCameraInitialized,
              galleryImage: _galleryImage,
              capturedImage: _capturedImage,
              latestDefects: _latest,
              maxHeight: maxImageHeight,
            ),
            ThumbnailStrip(
              key: _thumbnailStripKey,
              recentImages: _recentImages,
              onImageSelected: _handleImageSelected,
              onGenerateReport: _makeReportFromSelectedThumbnails,
              onImageDeleted: _handleImageDeleted,
            ),
            Container(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: ElevatedButton.icon(
                  onPressed: _isDetecting ? _captureAndStop : _startDetectAndCamera,
                  icon: Icon(_isDetecting ? Icons.camera : Icons.play_arrow, size: 20),
                  label: Text(
                    _isDetecting ? '사진 촬영' : '탐지',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDetecting ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_latest.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DefectSummaryPanel(
                        totalCount: _latest.length,
                        summaryChips: _buildDefectSummaryChips(),
                        detailChips: _buildDefectChips(),
                        onGenerateReport: _makeReportFromSelectedOrAll,
                        onAskAi: _askAi,
                      ),
                    ],
                    if (_advisorText != null) ...[
                      const SizedBox(height: 8),
                      AiResponsePanel(text: _advisorText!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
