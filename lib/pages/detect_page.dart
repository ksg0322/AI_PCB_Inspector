import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/detector_service.dart';
import '../models/pcb_defect_models.dart';
import '../services/ai_advisor.dart';
import '../services/report_generator.dart';
import '../models/captured_image.dart';
import '../services/detect_page_controller.dart';
import '../services/photo_saver.dart';
import '../widgets/stream_viewport.dart';
import '../widgets/control_panel.dart';
import '../widgets/defect_summary_panel.dart';
import '../widgets/ai_response_panel.dart';

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

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];

  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  List<DetectedDefect> _latest = const [];
  String? _advisorText;
  bool _isInitializingCamera = false;
  bool _isGalleryMode = false; // 갤러리 모드 여부
  
  // 프레임 처리량 제한을 위한 변수들
  bool _inferenceBusy = false;
  int _lastInferMs = 0;
  static const int _minIntervalMs = 80; // ≈12.5 FPS
  
  XFile? _galleryImage;
  XFile? _capturedImage; // 촬영한 이미지 저장
  List<CapturedImage> _capturedImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = DetectPageController(_detector);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      await _detector.initialize();
      setState(() {});
    } catch (e) {
      print('초기화 오류: $e');
    }
  }

  Future<void> _initializeCamera() async {
    if (_isCameraInitialized || _isInitializingCamera) return;
    
    if (_cameras.isEmpty) {
      print('카메라 목록이 비어있습니다. 카메라 목록을 다시 가져옵니다.');
      try {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) {
          print('사용 가능한 카메라가 없습니다.');
          return;
        }
      } catch (e) {
        print('카메라 목록 가져오기 실패: $e');
        return;
      }
    }
    
    try {
      _isInitializingCamera = true;
      print('카메라 초기화 시작');
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
        print('카메라 초기화 완료');
      }
    } catch (e) {
      print('카메라 초기화 오류: $e');
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
        print('📹 카메라 컨트롤러 해제 완료');
      }
    } catch (e) {
      print('⚠️ 카메라 dispose 오류: $e');
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
    // 갤러리/촬영 이미지 해제 후 카메라 미리보기로 전환
    setState(() {
      _galleryImage = null;
      _capturedImage = null;
      _isGalleryMode = false;
      _latest = [];
    });
    // 카메라가 초기화되지 않았다면 먼저 초기화
    if (!_isCameraInitialized) {
      await _initializeCamera();
      if (!_isCameraInitialized) return;
    }
    // 탐지 시작
    await _startDetect();
  }

  Future<void> _captureAndStop() async {
    if (!_isDetecting) return;
    
    // 사진 촬영 후 탐지 중지 (카메라는 유지)
    await _capturePhoto();
    await _stopDetect();
    // 카메라는 유지하여 촬영한 이미지를 계속 표시
  }

  Future<void> _startDetect() async {
    if (_camera == null || !_isCameraInitialized || _isDetecting) return;
    
    setState(() => _isDetecting = true);
    _inferenceBusy = false; // 추론 상태 초기화
    _lastInferMs = 0; // 마지막 추론 시간 초기화
    
    // CameraPreview에서 주기적으로 이미지 캡처하여 탐지
    _startPreviewDetection();
  }

  void _startPreviewDetection() {
    if (!_isDetecting) return;
    
    // 200ms마다 CameraPreview에서 이미지 캡처하여 탐지
    Future.delayed(const Duration(milliseconds: 200), () async {
      if (!_isDetecting || _camera == null || !_isCameraInitialized) return;
      
      // 카메라 컨트롤러 상태 확인
      if (!_camera!.value.isInitialized) {
        print('⚠️ 카메라가 초기화되지 않음, 탐지 중지');
        return;
      }
      
      // 처리량 제한: 추론 중이거나 최소 간격 미달 시 스킵
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_inferenceBusy || now - _lastInferMs < _minIntervalMs) {
        _startPreviewDetection(); // 다음 주기로 계속
        return;
      }
      
      _inferenceBusy = true;
      _lastInferMs = now;
      
      try {
        // CameraPreview에서 이미지 캡처 (임시 파일)
        final image = await _camera!.takePicture();
        print('🔍 CameraPreview 캡처: ${image.path}');
        
        // 캡처한 이미지로 탐지 수행 (CameraPreview와 동일한 해상도)
        final results = await _pageController.detectOnImagePath(image.path);
        print('🔍 탐지 완료 - 결과: ${results.length}개');
        
        if (mounted && _isDetecting) {
          setState(() {
            _latest = results;
          });
        }
        
        // 임시 파일 삭제
        try {
          await File(image.path).delete();
        } catch (e) {
          print('⚠️ 임시 파일 삭제 실패: $e');
        }
        
      } catch (e) {
        debugPrint('탐지 오류: $e');
        // 카메라 오류 시 탐지 중지
        if (e.toString().contains('Disposed CameraController') || 
            e.toString().contains('CameraException')) {
          print('❌ 카메라 오류로 인한 탐지 중지');
          await _stopDetect();
        }
      } finally {
        _inferenceBusy = false;
        if (_isDetecting) {
          _startPreviewDetection(); // 다음 주기로 계속
        }
      }
    });
  }

  Future<void> _stopDetect() async {
    if (!_isDetecting) return;
    
    setState(() => _isDetecting = false);
    _inferenceBusy = false; // 추론 상태 초기화
    
    // 카메라가 유효한 경우에만 스트림 중지
    if (_camera != null && _isCameraInitialized) {
      try {
        if (_camera!.value.isStreamingImages) {
          await _camera!.stopImageStream();
          print('📹 카메라 스트림 중지 완료');
        }
      } catch (e) {
        print('⚠️ 카메라 스트림 중지 오류: $e');
      }
    }
  }

  Future<void> _askAi() async {
    try {
      print('🤖 AI 문의 시작');
      final validDefects = _latest;
      final label = validDefects.isNotEmpty ? validDefects.first.label : 'Short_circuit';
      print('🔍 탐지된 결함 라벨: $label');
      print('📊 현재 유효한 탐지 결과 개수: ${validDefects.length}');
      
      final text = await _advisor.askAdvisor(defectLabel: label);
      print('✅ AI 응답 받음: ${text.length}자');
      print('📝 AI 응답 내용: $text');
      
      setState(() => _advisorText = text);
      print('🎯 UI 업데이트 완료');
    } catch (e) {
      print('❌ AI 문의 오류: $e');
      setState(() => _advisorText = 'AI 응답을 가져오는 중 오류가 발생했습니다: $e');
    }
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
      // 1. 사진 촬영
      final image = await _camera!.takePicture();
      print('📸 사진 촬영 완료: ${image.path}');
      
      // 2. 실시간 탐지 및 카메라 리소스 완전 해제
      if (_isDetecting) {
        await _stopDetect();
        print('⏹️ 실시간 탐지 중지');
      }
      // 프리뷰/이미지리더까지 포함한 카메라 리소스를 모두 해제하여 버퍼 릴리즈
      if (_isCameraInitialized) {
        await _disposeCamera();
        print('🧹 카메라 완전 해제(프리뷰/이미지 스트림 포함)');
      }
      
      // 3. 촬영한 사진을 별도로 탐지 (시스템 안정화를 위한 지연)
      print('🔍 촬영한 사진 탐지 시작');
      await Future.delayed(const Duration(milliseconds: 300));
      final capturedDefects = await _pageController.detectOnImagePath(image.path);
      print('✅ 촬영한 사진 탐지 완료: ${capturedDefects.length}개 결함 발견');
      
      // 4. 촬영한 이미지의 탐지 결과는 원본 좌표 그대로 사용 (실시간만 회전 적용)
      final transformedDefects = capturedDefects;
      
      // 5. 촬영한 사진을 저장소에 저장
      print('🔄 사진 저장 시작...');
      final savedPath = await PhotoSaver.savePhotoToGallery(image);
      if (savedPath != null) {
        print('✅ 사진 저장 성공: $savedPath');
      } else {
        print('❌ 사진 저장 실패');
      }
      
      // 6. 촬영한 사진과 탐지 결과를 저장
      final capturedImage = await _pageController.buildCaptured(image.path, transformedDefects);
      
      setState(() {
        _capturedImages.add(capturedImage);
        _capturedImage = image; // 촬영한 이미지 저장하여 계속 표시
        _latest = capturedDefects; // 촬영한 사진의 탐지 결과로 업데이트
        _isDetecting = false; // 탐지 상태를 false로 설정하여 UI 업데이트
      });
      
      // 7. 성공 메시지 표시
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
        _isGalleryMode = true; // 갤러리 모드로 전환
      });
      
      // 선택된 이미지로 탐지 실행
      print('🖼️ 갤러리 이미지 탐지 시작: ${image.path}');
      final results = await _pageController.detectOnImagePath(image.path);
      print('🖼️ 갤러리 이미지 탐지 완료: ${results.length}개 탐지됨');
      
      setState(() {
        _latest = results;
      });

      // 갤러리에서 선택한 이미지도 _capturedImages에 추가 (리포트 생성용)
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
  }

  void _clearImage() {
      setState(() {
        _galleryImage = null;
        _capturedImage = null;
        _latest = []; // 누적된 박스도 클리어
        _isGalleryMode = false; // 갤러리 모드 해제
      });

    // 촬영한 이미지 해제 시 카메라 스트림 상태 확인 및 정리
    if (_capturedImage != null && _camera != null && _isCameraInitialized) {
      try {
        _camera!.stopImageStream();
        print('📹 촬영한 이미지 해제 시 카메라 스트림 정리');
      } catch (e) {
        print('⚠️ 카메라 스트림 정리 오류: $e');
      }
    }

    // 이미지 해제 후 카메라가 해제되어 있다면 재초기화
    if (!_isCameraInitialized && _cameras.isNotEmpty) {
      _initializeCamera();
    }
  }
  

  // 결함 설명 생성 로직은 DefectSummaryUtil로 이동

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
    
    // 모든 촬영된 사진의 결함들을 수집 (모든 결함 포함)
    final allDefects = <DetectedDefect>[];
    for (final capturedImage in _capturedImages) {
      allDefects.addAll(capturedImage.defects);
    }
    
    await _report.generateAndShare(
      defects: allDefects, 
      advisorSummary: _advisorText,
      capturedImages: _capturedImages,
    );
  }


  Color _getDefectColor(String label) {
    final colorInt = PCBDefectModelConfig.defectColors[label];
    if (colorInt != null) {
      return Color(colorInt);
    }
    return Colors.grey;
  }

  List<Widget> _buildDefectChips() {
    // 모든 결함 표시 (신뢰도 필터링 제거)
    if (_latest.isEmpty) return [];
    
    // 각 결함 유형별로 번호를 매기기 위한 카운터
    final Map<String, int> defectCounters = {};
    final List<Widget> chips = [];
    
    for (final defect in _latest) {
      // 해당 결함 유형의 카운터 증가
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

  /// 결함 종류별 개수를 표시하는 위젯들 생성
  List<Widget> _buildDefectSummaryChips() {
    // 모든 결함 표시 (신뢰도 필터링 제거)
    if (_latest.isEmpty) return [];
    
    // 결함 종류별 개수 계산
    final Map<String, int> defectCounts = {};
    for (final defect in _latest) {
      defectCounts[defect.label] = (defectCounts[defect.label] ?? 0) + 1;
    }
    
    final List<Widget> summaryChips = [];
    
    // 각 결함 종류별로 요약 칩 생성
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

  // 오버레이 위젯은 widgets/defect_overlays.dart로 이동

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
          print('⚠️ 카메라 dispose 오류: $e');
        }
        _camera = null;
      }
      
      // 탐지 서비스 해제
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 메인 컨텐츠 영역 - 가변 크기 (오버플로우 방지)
            Expanded(
              flex: 6,
              child: StreamViewport(
                camera: _camera,
                isCameraInitialized: _isCameraInitialized,
                galleryImage: _galleryImage,
                capturedImage: _capturedImage,
                latestDefects: _latest,
              ),
            ),
            
            // 하단 컨트롤 패널 - 가변 크기 (오버플로우 방지)
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(6),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ControlPanel(
                        isGalleryMode: _isGalleryMode,
                        isCameraInitialized: _isCameraInitialized,
                        isDetecting: _isDetecting,
                        capturedImagesCount: _capturedImages.length,
                        hasImage: _galleryImage != null || _capturedImage != null,
                        onStartDetectOrCapture: _isDetecting ? _captureAndStop : _startDetectAndCamera,
                        onPickImage: _pickImageFromGallery,
                        onClearImage: _clearImage,
                        onAskAi: _askAi,
                        onMakeReport: _makeReport,
                      ),
                  // 탐지 결과 표시 (모든 결함)
                  if (_latest.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DefectSummaryPanel(
                      totalCount: _latest.length,
                      summaryChips: _buildDefectSummaryChips(),
                      detailChips: _buildDefectChips(),
                    ),
                  ],
                  
                  // AI 답변 표시
                  if (_advisorText != null) ...[
                    const SizedBox(height: 8),
                    AiResponsePanel(text: _advisorText!),
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
}