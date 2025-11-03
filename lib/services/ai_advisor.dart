import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import 'ai_prompt.dart';

class AiAdvisorService {
  final String modelName;
  AiAdvisorService({this.modelName = 'gemini-2.5-flash-lite'});

  Future<String> askAdvisorWithNoDefect({String message = ''}) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=${ApiKeys.geminiApiKey}',
    );

    final body = {
      'systemInstruction': {
        'role': 'system',
        'parts': [
          {
            'text': '''페르소나 설정 (역할 부여)
당신의 목표는 발견된 PCB 결함을 정확하게 분석하고, 결함을 해결할 수 있도록 돕는 것입니다.
답변은 100자 이내로 작성해주세요.''',
          },
        ],
      },
      'contents': [
        {
          'parts': [
            {'text': (message.isEmpty) ? '안녕하세요.' : message},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.5, // 약간의 창의성을 허용
        'topP': 0.95,
      },
    };

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      return 'AI 응답 오류: ${resp.statusCode} ${resp.body}';
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return '응답 없음';
    final content = candidates.first['content'];
    if (content == null) return '응답 없음';
    final parts = content['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return '응답 없음';
    final text = parts.first['text'] as String?;
    return text ?? '응답 없음';
  }

  Future<String> askAdvisorForMultipleDefects({
    required List<String> defectLabels,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=${ApiKeys.geminiApiKey}',
    );
    final prompt = AiPrompt.getPromptForDefects(defectLabels);

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'topP': 0.90,
      },
    };

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      return 'AI 응답 오류: ${resp.statusCode} ${resp.body}';
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return '응답 없음';
    final content = candidates.first['content'];
    if (content == null) return '응답 없음';
    final parts = content['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return '응답 없음';
    final text = parts.first['text'] as String?;
    return text ?? '응답 없음';
  }
}
