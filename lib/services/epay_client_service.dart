import 'dart:convert';
import 'package:http/http.dart' as http;
import '../network/http_client.dart'; // 引入平台的统一请求工具

class EpayClientConfig {
  // 易支付的官方请求物理前缀
  static const String apiUrl = 'https://www.qingtianyzff.com/';
}

class EpayClientService {
  /// 🌟 核心中继：向应用服务器发起安全参数加签请求（自动使用 HttpClient 携带 Token）
  Future<Map<String, String>> _getSignaturesFromServer({
    required Map<String, dynamic> rawParams,
  }) async {
    try {
      // 🌟 统一使用封装好的 HttpClient，自动附加 Token，安全极简
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-pay/sign',
        data: {'params': rawParams},
      );

      if (res.datas != null) {
        final signedData = Map<String, dynamic>.from(res.datas!);
        return signedData.map((key, value) => MapEntry(key.toString(), value.toString()));
      } else {
        throw Exception('应用服务器签名被拒绝');
      }
    } catch (e) {
      throw Exception('网络签名握手失败: $e');
    }
  }

  /// 🌟 客户端主动请求易支付：直接创建付款订单
  Future<Map<String, dynamic>> createPaymentDirectly({
    required Map<String, dynamic> params,
  }) async {
    try {
      // 1. 向 Zeabur 国外服务器安全申请代签请求
      final signedBodyParams = await _getSignaturesFromServer(
        rawParams: params,
      );

      // 2. 拿到代签包后，由身处国内网络环境的客户端直接向易支付物理接口发起下单
      final url = Uri.parse('${EpayClientConfig.apiUrl}api/pay/create');

      // 🌟🌟 专属控制台高亮调试日志：请求发送 🌟🌟
      print('==================== 易支付 (qingtianyzff) 请求 ====================');
      print('➤ 接口地址: $url');
      print('➤ 提交数据: ${jsonEncode(signedBodyParams)}');
      print('==================================================================');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: signedBodyParams,
      );

      // 🌟🌟 专属控制台高亮调试日志：数据接收 🌟🌟
      print('==================== 易支付 (qingtianyzff) 响应 ====================');
      print('➤ 接口地址: $url');
      print('➤ HTTP 状态码: ${response.statusCode}');
      print('➤ 平台返回报文: ${response.body.trim()}');
      print('==================================================================');

      if (response.statusCode == 200) {
        return jsonDecode(response.body.trim()) as Map<String, dynamic>;
      } else {
        return {'code': -1, 'msg': '支付网关通信失败 HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'code': -1, 'msg': '下单链路断开: $e'};
    }
  }

  /// 🌟 客户端主动请求易支付：反查真实的订单详情（包含平台签名）
  Future<Map<String, dynamic>> queryOrderDirectly({
    required String outTradeNo,
  }) async {
    try {
      // 1. 向 Zeabur 后端安全申请代签请求
      final signedBodyParams = await _getSignaturesFromServer(
        rawParams: {'out_trade_no': outTradeNo},
      );

      // 2. 客户端直接反查易支付获取官方带平台签名的原装支付状态报文
      final url = Uri.parse('${EpayClientConfig.apiUrl}api/pay/query');

      // 🌟🌟 专属控制台高亮调试日志：请求发送 🌟🌟
      print('==================== 易支付 (qingtianyzff) 查询请求 ====================');
      print('➤ 接口地址: $url');
      print('➤ 提交数据: ${jsonEncode(signedBodyParams)}');
      print('====================================================================');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: signedBodyParams,
      );

      // 🌟🌟 专属控制台高亮调试日志：数据接收 🌟🌟
      print('==================== 易支付 (qingtianyzff) 查询响应 ====================');
      print('➤ 接口地址: $url');
      print('➤ HTTP 状态码: ${response.statusCode}');
      print('➤ 平台返回报文: ${response.body.trim()}');
      print('====================================================================');

      if (response.statusCode == 200) {
        return jsonDecode(response.body.trim()) as Map<String, dynamic>;
      } else {
        return {'code': -1, 'msg': '直连平台订单查询失败 HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'code': -1, 'msg': '直连查询网络异常: $e'};
    }
  }
}