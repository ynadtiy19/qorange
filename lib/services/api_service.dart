// 负责提供 Cloudinary 媒体上传、CometChat 微服务翻译和 GIF 图检索接口
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApiService {
  static const String cloudinaryUrl = 'https://api.cloudinary.com/v1_1/ddgzciyug/image/upload';
  static const String cloudinaryPreset = 'supplyuuu';
  static const String translationUrl = 'https://message-translation-in.cc-cluster-2.io/v2/translate';

  static const Map<String, String> translationHeaders = {
    'accept': ' application/json',
    'accept-language': ' zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'appid': '267879a77f4b29cd',
    'authorization': 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImNjcHJvX2p3dF9yczI1Nl9rZXkxIn0.eyJpc3MiOiJodHRwczovL2FwaWNsaWVudC1pbi5jb21ldGNoYXQuaW8iLCJhdWQiOiJydGMtaW4uY29tZXRjaGF0LmlvIiwiaWF0IjoxNzY1ODE1ODU2LCJzdWIiOiJbMjY3ODc5YTc3ZjRiMjljZF1kZW1vXzE3NjU3ODQ5NDAzMjhfMjkiLCJuYmYiOjE3NjU4MTIyNTYsImV4cCI6MTc3MTA3NTg1NiwiZGF0YSI6eyJhcHBJZCI6IjI2Nzg3OWE3N2Y0YjI5Y2QiLCJyZWdpb24iOiJpbiIsImF1dGhUb2tlbiI6ImRlbW9fMTc2NTc4NDk0MDMyOF8yOV8xNzY1Nzg2NDY5YTU0YmEwYWVjYWRiNjljZmNjZDk5MTQ1ZmIzM2FiIiwidXNlciI6eyJ1aWQiOiJkZW1vXzE3NjU3ODQ5NDAzMjhfMjkiLCJuYW1lIjoiUmVuZWUgVG9ycCIsImF2YXRhciI6Imh0dHBzOi8vZGF0YS1pbi5jb21ldGNoYXQuaW8vMjY3ODc5YTc3ZjRiMjljZC9hdmF0YXJzL2RlbW9fMTc2NTc4NDk0MDMyOF8yOS53ZWJwIjob3V0bGluZSIsInJvbGUiOiJkZW1vIn19fQ.hVWd-T2iAIYNux1vxmzM7m5C5W7jFNzEn-69qJOspr8m17qqu7NLC_onNzwFIcIrq7bM3U8fJuTOCYwSPf7ZL-U80M6Xzj0OSxoao3NhbC-n9cKXQp4pHpqrNB2LdYuxrWZkdjiQSIwo16rqIIsojy2MFwT4rYNpHEBvlRvha6g',
    'authtoken': 'demo_1765784940328_29_1765786469a54ba0aecadb69cfccd99145fb33ab',
    'cache-control': ' no-cache',
    'chatapiversion': ' v3.0',
    'content-type': ' application/json',
    'origin': ' https://app.cometchat.com',
  };

  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> copyImageFromUrl(String imageUrl) async {
    try {
      if (kIsWeb || Platform.isIOS) {
        await Clipboard.setData(ClipboardData(text: imageUrl));
        return;
      }
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Download image failed');
      }
      final Uint8List bytes = response.bodyBytes;
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/copied_image_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Clipboard.setData(ClipboardData(text: file.path));
    } catch (e) {
      debugPrint('Copy image error: $e');
      await Clipboard.setData(ClipboardData(text: imageUrl));
    }
  }

  static Future<String?> uploadImage(File imageFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(cloudinaryUrl));
      request.fields['upload_preset'] = cloudinaryPreset;
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        return jsonDecode(respStr)['secure_url'];
      }
      return null;
    } catch (e) {
      debugPrint("Upload Error: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> translate(
      String text,
      String targetLang, {
        String? system,
      }) async {
    if (text.trim().isEmpty) return null;
    try {
      var request = http.Request('POST', Uri.parse(translationUrl));
      request.headers.addAll(translationHeaders);

      final bodyData = {
        "msgId": DateTime.now().millisecondsSinceEpoch.toString(),
        "text": text,
        "languages": [targetLang],
        if (system != null) "system": system,
      };

      request.body = jsonEncode(bodyData);
      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final json = jsonDecode(responseBody);
        if (json['data'] != null && json['data']['translations'] != null) {
          final translations = json['data']['translations'] as List;
          if (translations.isNotEmpty) {
            final t = translations.first;
            return {
              'language': t['language_translated'] ?? targetLang,
              'text': t['message_translated'] ?? text,
            };
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("Translate Error: $e");
      return null;
    }
  }

  static Future<List<String>> fetchIntercomGifs({String query = ''}) async {
    try {
      var headers = {
        'Accept': ' */*',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': ' https://www.elegantthemes.com',
        'User-Agent': ' Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
        'Cache-Control': ' no-cache',
        'Pragma': ' no-cache',
      };

      var request = http.Request('POST', Uri.parse('https://api-iam.intercom.io/messenger/web/gifs'));
      request.bodyFields = {
        'app_id': 'hrpt54hy',
        'v': '3',
        'g': '5839509c7ebc3d18eebb2635b5383d33bd89d98f',
        's': '1ab367b2-343a-4efa-b458-03f45cae95e2',
        'r': 'https://www.elegantthemes.com/',
        'platform': 'web',
        'installation_type': 'js-snippet',
        'installation_version': 'undefined',
        'Idempotency-Key': '1fb41c34ab9cdd74',
        'internal': '',
        'is_intersection_booted': 'false',
        'page_title': 'elegant_theme_title'.tr,
        'user_active_company_id': '-1',
        'user_data': '{"anonymous_id":"80109712-c126-4c90-a265-c09853d7450c"}',
        'query': query,
        'referer': 'https://www.elegantthemes.com/join/',
        'device_identifier': 'b015be9f-e920-47c8-829e-9d2cc6443e5a',
      };
      request.headers.addAll(headers);
      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        String responseStr = await response.stream.bytesToString();
        final json = jsonDecode(responseStr);
        if (json['results'] != null) {
          final results = json['results'] as List;
          return results.map<String>((e) => e['url'].toString()).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("Fetch GIF Error: $e");
      return [];
    }
  }
}