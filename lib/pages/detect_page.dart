import 'dart:async';
import 'dart:io'; // File 클래스를 사용하기 위해 추가
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // image_picker 추가
import '../services/detector.dart';
import '../services/ai_advisor.dart';
import '../services/report_generator.dart';

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

class DetectPage extends StatefulWidget {
  const DetectPage({super.key});

  @override
  State<DetectPage> createState() => _DetectPageState();
}

class _DetectPageState extends State<DetectPage> with WidgetsBindingObserver {
  final DetectorService _detector = DetectorService();
  final AiAdvisorService _advisor = AiAdvisorService();
  final ReportGenerator _report = ReportGenerator();

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];

  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  List<DetectedDefect> _latest = const [];
  String? _advisorText;
  DateTime? _lastDetectionTime;
  bool _isInitializingCamera = false;
  
  // 갤러리에서 선택된 이미지를 표시하기 위한 변수
  XFile? _galleryImage;

  // 촬영한 사진과 탐지 결과 저장
  List<CapturedImage> _capturedImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      print('📱 카메라 목록 확인 중...');
      _cameras = await availableCameras();
      await _detector.initialize();
      print('✅ 초기화 완료!');
      setState(() {});
    } catch (e) {
      print('❌ 초기화 오류: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitialized || _cameras.isEmpty || _isInitializingCamera) return;
    
    try {
      _isInitializingCamera = true;
      print('📷 카메라 초기화 중...');
      final back = _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => _cameras.first);
      _camera = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      print('✅ 카메라 준비 완료!');
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      print('❌ 카메라 초기화 오류: $e');
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _disposeCamera() async {
    try {
      await _stopDetect();
      await _camera?.dispose();
    } catch (e) {
      print('⚠️ 카메라 dispose 오류: $e');
    } finally {
      _camera = null;
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      } else {
        _isCameraInitialized = false;
      }
    }
  }

  Future<void> _startDetect() async {
    if (_camera == null || !_isCameraInitialized || _isDetecting) return;
    setState(() => _isDetecting = true);
    await _camera!.startImageStream((CameraImage image) async {
      if (!_isDetecting) return;
      
      // 성능 최적화: 탐지 빈도 제한 (3초마다)
      final now = DateTime.now();
      if (_lastDetectionTime != null && 
          now.difference(_lastDetectionTime!).inMilliseconds < 3000) {
        return;
      }
      _lastDetectionTime = now;
      
           try {
             // YUV 전체 이미지를 사용하여 정확도 높은 탐지 수행
             final results = await _detector.detectOnFrame(cameraImage: image);
             print('📱 UI 업데이트: ${results.length}개 탐지 결과 받음');
             setState(() => _latest = results);
             print('📱 UI 상태 업데이트 완료: _latest.length = ${_latest.length}');
           } catch (e) {
             print('❌ 탐지 오류: $e');
           }
    });
  }

  Future<void> _stopDetect() async {
    if (_camera == null || !_isDetecting) return;
    setState(() => _isDetecting = false);
    try {
      await _camera!.stopImageStream();
      print('🛑 탐지 중지됨');
    } catch (e) {
      print('⚠️ 탐지 중지 오류: $e');
    }
  }

  Future<void> _askAi() async {
    final label = _latest.isNotEmpty ? _latest.first.label : 'Short_circuit';
    final text = await _advisor.askAdvisor(defectLabel: label);
    setState(() => _advisorText = text);
  }

  Future<void> _capturePhoto() async {
    if (_camera == null || !_isCameraInitialized) return;
    
    // 갤러리 이미지가 있으면 카메라 촬영을 막음
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
      
      // 현재 탐지된 결함들을 설명으로 생성
      String description = _generateDefectDescription(_latest);
      
      // 촬영한 사진과 탐지 결과를 저장
      final capturedImage = CapturedImage(
        imagePath: image.path,
        defects: List.from(_latest),
        timestamp: DateTime.now(),
        description: description,
      );
      
      setState(() {
        _capturedImages.add(capturedImage);
      });
      
      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('사진이 저장되었습니다. ${_latest.length}개의 결함이 탐지되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
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

  Future<void> _pickImageFromGallery() async {
    // 실시간 탐지 중지
    if (_isDetecting) {
      await _stopDetect();
    }

    // 갤러리로 전환 시 카메라 완전 해제 (Camerax orientation listener 잔존 방지)
    if (_isCameraInitialized) {
      await _disposeCamera();
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _galleryImage = image;
        _latest = []; // 이전 탐지 결과 초기화
      });
      
      // 선택된 이미지로 탐지 실행
      final results = await _detector.detectOnImagePath(image.path);
      print('📱 갤러리 탐지 결과: ${results.length}개 받음');
      setState(() {
        _latest = results;
      });
      print('📱 갤러리 UI 상태 업데이트 완료: _latest.length = ${_latest.length}');
    }
  }

  void _clearGalleryImage() {
    setState(() {
      _galleryImage = null;
      _latest = [];
    });

    // 갤러리 이미지 해제 후 카메라가 해제되어 있다면 재초기화
    if (!_isCameraInitialized && _cameras.isNotEmpty) {
      _initializeCamera();
    }
  }

  String _generateDefectDescription(List<DetectedDefect> defects) {
    if (defects.isEmpty) {
      return '결함이 탐지되지 않았습니다.';
    }
    
    final counts = <String, int>{};
    for (final defect in defects) {
      counts[defect.label] = (counts[defect.label] ?? 0) + 1;
    }
    
    final descriptions = counts.entries.map((entry) {
      return '${entry.key} ${entry.value}건';
    }).join(', ');
    
    return '총 ${defects.length}건의 결함: $descriptions';
  }

  Future<void> _makeReport() async {
    if (_capturedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('리포트를 생성하려면 먼저 사진을 촬영해주세요.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 모든 촬영된 사진의 결함들을 수집
    final allDefects = <DetectedDefect>[];
    for (final capturedImage in _capturedImages) {
      allDefects.addAll(capturedImage.defects);
    }
    
    await _report.generateAndShare(defects: allDefects, advisorSummary: _advisorText);
  }

  Widget _buildDetectionOverlay(DetectedDefect defect) {
    return Positioned(
      left: defect.bbox.left,
      top: defect.bbox.top,
      child: Container(
        width: defect.bbox.width,
        height: defect.bbox.height,
        decoration: BoxDecoration(
          border: Border.all(
            color: _getDefectColor(defect.label),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _getDefectColor(defect.label),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${defect.label} (${(defect.confidence * 100).toInt()}%)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDefectColor(String label) {
    switch (label) {
      case 'Dry_joint':
        return Colors.orange;
      case 'Short_circuit':
        return Colors.red;
      case 'PCB_damage':
        return Colors.purple;
      case 'Incorrect_installation':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
      _stopDetect();
      _camera?.dispose();
      _detector.dispose();
    } catch (e) {
      print('⚠️ dispose 오류: $e');
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
        _disposeCamera();
        break;
      case AppLifecycleState.resumed:
        // 갤러리 모드가 아니고 카메라가 해제되어 있으면 재초기화
        if (mounted && _galleryImage == null && !_isCameraInitialized) {
          _initializeCamera();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('AI PCB Inspector'),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      body: SafeArea(
        child: Column(
          children: [
            // 메인 컨텐츠 영역 - 가변 크기 (오버플로우 방지)
            Expanded(
              flex: 6,
              child: _isCameraInitialized
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final double viewW = constraints.maxWidth;
                        final double viewH = constraints.maxHeight;

                        Widget imageWidget;
                        int srcW;
                        int srcH;
                        if (_galleryImage != null) {
                          imageWidget = Image.file(File(_galleryImage!.path), fit: BoxFit.contain);
                          // 갤러리의 원본 크기는 탐지 결과에 저장됨. 없으면 미리보기 비율로 가정
                          srcW = _latest.isNotEmpty ? _latest.first.sourceWidth : viewW.toInt();
                          srcH = _latest.isNotEmpty ? _latest.first.sourceHeight : viewH.toInt();
                        } else {
                          imageWidget = CameraPreview(_camera!);
                          // 카메라 프레임 크기: controller의 value.previewSize는 가로세로가 바뀌어 들어오기도 함
                          final s = _camera!.value.previewSize;
                          if (s != null) {
                            srcW = s.width.toInt();
                            srcH = s.height.toInt();
                          } else {
                            srcW = viewW.toInt();
                            srcH = viewH.toInt();
                          }
                        }

                        // letterbox 계산 (BoxFit.contain과 동일한 수학)
                        final double scale = (viewW / srcW).clamp(0, double.infinity) < (viewH / srcH).clamp(0, double.infinity)
                            ? viewW / srcW
                            : viewH / srcH;
                        final double drawW = srcW * scale;
                        final double drawH = srcH * scale;
                        final double offsetX = (viewW - drawW) / 2.0;
                        final double offsetY = (viewH - drawH) / 2.0;

                        return Stack(
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
                            if (_latest.isNotEmpty)
                              ..._latest.map((defect) {
                                // 원본 좌표 → 뷰 좌표 변환
                                final double left = offsetX + defect.bbox.left * scale;
                                final double top = offsetY + defect.bbox.top * scale;
                                final double w = defect.bbox.width * scale;
                                final double h = defect.bbox.height * scale;
                                return Positioned(
                                  left: left,
                                  top: top,
                                  child: Container(
                                    width: w,
                                    height: h,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _getDefectColor(defect.label),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    )
                  : _buildWelcomeScreen(),
            ),
            
            // 하단 컨트롤 패널 - 가변 크기 (오버플로우 방지)
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.grey[100],
                padding: const EdgeInsets.all(6), // 패딩 더 줄임
                child: SingleChildScrollView( // 스크롤 가능하게 만들기
                  child: Column(
                  children: [
                  // 카메라 제어 버튼들
                  if (!_isCameraInitialized) ...[
                    ElevatedButton.icon(
                      onPressed: _initializeCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('카메라 시작'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isDetecting ? _stopDetect : _startDetect,
                          icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow, size: 16),
                          label: Text(_isDetecting ? '탐지 중지' : '탐지 시작', style: const TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isDetecting ? Colors.red : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _capturePhoto,
                          icon: const Icon(Icons.camera, size: 16),
                          label: const Text('사진 촬영', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickImageFromGallery,
                          icon: const Icon(Icons.photo_library, size: 16),
                          label: const Text('갤러리', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        if (_galleryImage != null)
                          ElevatedButton.icon(
                            onPressed: _clearGalleryImage,
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _askAi,
                          icon: const Icon(Icons.chat, size: 16),
                          label: const Text('AI 문의', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _makeReport,
                          icon: const Icon(Icons.description, size: 16),
                          label: Text('리포트 생성${_capturedImages.isNotEmpty ? ' (${_capturedImages.length})' : ''}', style: const TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  // 탐지 결과 표시
                  if (_latest.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '탐지된 결함:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: _latest.map((defect) => Chip(
                              label: Text(
                                '${defect.label} (${(defect.confidence * 100).toInt()}%)',
                                style: const TextStyle(fontSize: 10),
                              ),
                              backgroundColor: _getDefectColor(defect.label).withOpacity(0.3),
                              labelStyle: TextStyle(color: _getDefectColor(defect.label)),
                            )).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // AI 답변 표시
                  if (_advisorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI 어드바이저 답변:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _advisorText!,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 100,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 32),
              const Text(
                'AI PCB Inspector',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: const Text(
                  'PCB 불량을 실시간으로 탐지하고\nAI 어드바이저의 도움을 받아\n문제를 해결해보세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                child: const Text(
                  '위의 "카메라 시작" 버튼을 눌러\n검사를 시작하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

