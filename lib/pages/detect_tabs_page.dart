import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/pcb_defect_models.dart';
import '../models/captured_image.dart';
import 'detect_page.dart';
import 'ai_chat_page.dart';

class DetectTabsPage extends StatefulWidget {
  const DetectTabsPage({super.key});

  @override
  State<DetectTabsPage> createState() => _DetectTabsPageState();
}

class _DetectTabsPageState extends State<DetectTabsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DetectedDefect> _latestDefects = [];
  String? _advisorText;

  // DetectPage 상태를 저장할 변수들
  List<CapturedImage> _capturedImages = [];
  List<XFile> _recentImages = [];
  XFile? _galleryImage;
  XFile? _capturedImage;
  List<DetectedDefect> _selectedDefectsSummary = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateDefects(List<DetectedDefect> defects) {
    setState(() {
      _latestDefects = defects;
    });
  }

  void _updateSelectedDefectsSummary(List<DetectedDefect> defects) {
    setState(() {
      _selectedDefectsSummary = defects;
    });
  }

  void _handleAiResponseReady(String? text) {
    setState(() {
      _advisorText = text;
      _tabController.index = 1;
    });
  }

  void _updateCapturedImages(List<CapturedImage> images) {
    setState(() {
      _capturedImages = images;
    });
  }

  void _updateRecentImages(List<XFile> images) {
    setState(() {
      _recentImages = images;
    });
  }

  void _updateGalleryImage(XFile? image) {
    setState(() {
      _galleryImage = image;
    });
  }

  void _updateCapturedImage(XFile? image) {
    setState(() {
      _capturedImage = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 채팅 탭에서는 뒤로가기를 누르면 탐지 탭으로 이동
        if (_tabController.index == 1) {
          setState(() {
            _tabController.index = 0;
          });
          return false; // 라우트 pop 방지
        }
        // 탐지 탭에서는 뒤로가기 동작 막기 (홈으로 돌아가지 않음)
        return false;
      },
      child: Scaffold(
        body: TabBarView(
          controller: _tabController,
          children: [
            // 탐지 탭
            DetectPage(
              key: const PageStorageKey<String>('detectPage'),
              onDefectsUpdated: _updateDefects,
              onCapturedImagesUpdated: _updateCapturedImages,
              onRecentImagesUpdated: _updateRecentImages,
              onGalleryImageUpdated: _updateGalleryImage,
              onCapturedImageUpdated: _updateCapturedImage,
              onSelectedDefectsUpdated: _updateSelectedDefectsSummary,
              onAiResponseReady: _handleAiResponseReady,
              initialCapturedImages: _capturedImages,
              initialRecentImages: _recentImages,
              initialGalleryImage: _galleryImage,
              initialCapturedImage: _capturedImage,
              advisorText: _advisorText,
            ),
            // AI 채팅 탭
            Builder(builder: (context) {
              final defectsForChat = _selectedDefectsSummary.isNotEmpty
                  ? _selectedDefectsSummary
                  : _latestDefects;

              return AiChatPage(
                key: const PageStorageKey('chat_tab'),
                detectedDefects: defectsForChat,
                advisorText: _advisorText,
              );
            }),
          ],
        ),
        bottomNavigationBar: Container(
          color: Colors.green,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60, // <- 필요 시 여기 숫자로 높이 조절
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 2,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                tabs: const [
                  Tab(
                    iconMargin: EdgeInsets.only(bottom: 2),
                    icon: Icon(Icons.camera_alt, size: 22),
                    text: '탐지',
                  ),
                  Tab(
                    iconMargin: EdgeInsets.only(bottom: 2),
                    icon: Icon(Icons.chat, size: 22),
                    text: 'AI 채팅',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
