// 执行 Delta 文档的提取、编码、API翻译与回填还原逻辑
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'api_service.dart';

class QuillTranslationService {
  static final QuillTranslationService _instance = QuillTranslationService._internal();
  factory QuillTranslationService() => _instance;
  QuillTranslationService._internal();

  static final RegExp _anchorRegex = RegExp(
    r'\[([\s\S]*?)\]\s*\(id\s*:\s*(\d+)(:[\w]+)?\s*\)',
    multiLine: true,
  );

  Future<Delta> translateDelta(Delta originalDelta, String targetLang) async {
    try {
      if (originalDelta.isEmpty) return Delta();

      final encodingResult = _encode(originalDelta);
      final String textToTranslate = encodingResult.payload;

      if (textToTranslate.trim().isEmpty) {
        return originalDelta;
      }

      const String systemPrompt =
          "Role: Translator. "
          "Task: Translate the text inside the Markdown brackets `[...]` into the target language. "
          "CRITICAL RULES: "
          "1. KEEP the Link ID `(id:N)` EXACTLY as is. "
          "2. Do NOT nest links. "
          "3. Translate only the text content inside `[]`."
          "4. Keep formatting symbols intact.";

      final result = await ApiService.translate(
        textToTranslate,
        targetLang,
        system: systemPrompt,
      );

      if (result == null || result['text'] == null) {
        throw Exception("Translation API returned empty response");
      }

      final Delta translatedDelta = _decode(originalDelta, result['text']);
      return translatedDelta;
    } catch (e) {
      debugPrint("QuillTranslationService Error: $e");
      return originalDelta;
    }
  }

  ({String payload, int count}) _encode(Delta delta) {
    final StringBuffer buffer = StringBuffer();
    int count = 0;
    final List<Operation> ops = delta.toList();

    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];
      final data = op.data;
      final attrs = op.attributes;

      if (data is String) {
        if (data == '\n') continue;
        if (data.trim().isNotEmpty) {
          final escapedText = _escapeSpecialChars(data);
          buffer.write('[$escapedText](id:$i)');
          count++;
        }
      } else if (data is Map && attrs != null && attrs.containsKey('alt')) {
        final altText = attrs['alt'];
        if (altText is String && altText.isNotEmpty) {
          final escapedAlt = _escapeSpecialChars(altText);
          buffer.write('[$escapedAlt](id:$i:alt)');
          count++;
        }
      }
    }

    return (payload: buffer.toString(), count: count);
  }

  Delta _decode(Delta originalDelta, String translatedText) {
    final List<dynamic> jsonList = jsonDecode(jsonEncode(originalDelta.toJson()));
    final Delta newDelta = Delta.fromJson(jsonList);
    final List<Operation> newOps = newDelta.toList();
    final Iterable<RegExpMatch> matches = _anchorRegex.allMatches(translatedText);

    for (final match in matches) {
      String content = match.group(1) ?? "";
      final String indexStr = match.group(2) ?? "-1";
      final int index = int.tryParse(indexStr) ?? -1;
      final String? subType = match.group(3);

      if (index < 0 || index >= newOps.length) continue;
      content = _unescapeSpecialChars(content);

      if (subType == null || subType.isEmpty) {
        final originalOp = newOps[index];
        final originalData = originalOp.data;
        if (originalData is String) {
          newOps[index] = Operation.insert(content, originalOp.attributes);
        }
      } else if (subType == ':alt') {
        final originalOp = newOps[index];
        final originalData = originalOp.data;
        if (originalData is Map) {
          final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(originalOp.attributes ?? {});
          newAttrs['alt'] = content;
          newOps[index] = Operation.insert(originalData, newAttrs);
        }
      }
    }

    return Delta.fromOperations(newOps);
  }

  String _escapeSpecialChars(String input) {
    return input.replaceAll('[', '&#91;').replaceAll(']', '&#93;');
  }

  String _unescapeSpecialChars(String input) {
    return input.replaceAll('&#91;', '[').replaceAll('&#93;', ']');
  }
}