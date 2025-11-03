import 'package:flutter/material.dart';
import '../models/pcb_defect_models.dart';
import '../utils/defect_overlay_util.dart';
import '../services/ai_advisor.dart';

class AiChatPage extends StatefulWidget {
  final List<DetectedDefect> detectedDefects;
  final String? advisorText;

  const AiChatPage({
    super.key,
    required this.detectedDefects,
    this.advisorText,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage>
    with AutomaticKeepAliveClientMixin<AiChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _lastAdvisorText;
  final AiAdvisorService _advisor = AiAdvisorService();

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _lastAdvisorText = widget.advisorText;
  }

  void _initializeChat() {
    /// 채팅이 비어있을 때만 인사말을 추가합니다.
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessage(
          text:
              '안녕하세요! PCB 진단 AI 어드바이저입니다.\n탐지된 결함이 있거나 궁금한 점이 있다면 언제든 문의해 주세요!',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant AiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // DetectPage에서 새 AI 응답이 오면 채팅에 추가
    if (widget.advisorText != null && widget.advisorText!.isNotEmpty) {
      if (widget.advisorText != _lastAdvisorText) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: '${widget.advisorText!}\n\n *답변을 저장 하시려면 탐지 페이지에 이미지 썸네일을 길게 눌러 선택하고 리포트 생성 버튼을 눌러주세요.*',
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _lastAdvisorText = widget.advisorText;
        });
        // 새 메시지에 스크롤 맞추기
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _messageController.clear();
    });

    // 스크롤을 맨 아래로
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      // 채팅에서는 항상 일반 대화 API를 사용
      final String reply = await _advisor.askAdvisorWithNoDefect(message: text);

      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(text: reply, isUser: false, timestamp: DateTime.now()),
        );
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: 'AI 응답 중 오류가 발생했습니다: $e',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 채팅',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              // 채팅 기록 초기화
              setState(() {
                _messages.clear();
                _initializeChat();
              });
            },
            icon: const Icon(Icons.refresh),
            tooltip: '채팅 초기화',
          ),
        ],
      ),
      body: Column(
        children: [
          // 탐지된 결함 정보 표시
          if (widget.detectedDefects.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '탐지된 결함:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _buildSummaryChips(),
                  ),
                ],
              ),
            ),

          // 채팅 메시지 목록
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),

          // 메시지 입력 영역
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'AI에게 질문하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSummaryChips() {
    if (widget.detectedDefects.isEmpty) return const [];

    final Map<String, int> defectCounts = {};
    for (final defect in widget.detectedDefects) {
      defectCounts[defect.label] = (defectCounts[defect.label] ?? 0) + 1;
    }

    final List<Widget> summaryChips = [];
    defectCounts.forEach((label, count) {
      final color = DefectOverlayUtil.getFlutterColor(label);
      summaryChips.add(
        Chip(
          label: Text(
            '$label: $count개',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          backgroundColor: color.withOpacity(0.2),
          labelStyle: TextStyle(color: color),
          side: BorderSide(color: color, width: 1),
        ),
      );
    });

    return summaryChips;
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple[100],
              child: Icon(Icons.smart_toy, size: 16, color: Colors.purple),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.green[300] : Colors.grey[200],
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomLeft: message.isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: message.isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: message.isUser ? Colors.white70 : Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              child: const Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
