import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import 'ai_prompt.dart';

class AiAdvisorService {
  final String modelName;
  AiAdvisorService({this.modelName = 'gemini-2.5-flash-lite'});

  Future<String> askAdvisor({required String defectLabel}) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=${ApiKeys.geminiApiKey}');
    final prompt = AiPrompt.getPromptForDefect(defectLabel);

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
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

