import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/chat_message_model.dart';
import '../core/storage/secure_storage.dart';

class ChatRepository {
  final _dio = DioClient.instance.dio;

  Future<ChatMessage> sendMessage(int groupId, String content) async {
    try {
      final response = await _dio.post(
        ApiConfig.groupMessages(groupId),
        data: {'content': content},
      );
      final message = ChatMessage.fromJson(response.data['data']);
      final myId = await SecureStorageService.instance.userId;
      message.isMe = message.userId == myId;
      return message;
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<List<ChatMessage>> getMessages(int groupId, {int? before, int limit = 30}) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
      };
      if (before != null) {
        queryParams['before'] = before;
      }

      final response = await _dio.get(
        ApiConfig.groupMessages(groupId),
        queryParameters: queryParams,
      );

      final List<dynamic> data = response.data['data'] ?? [];
      final myId = await SecureStorageService.instance.userId;
      
      return data.map((json) {
        final msg = ChatMessage.fromJson(json);
        msg.isMe = msg.userId == myId;
        return msg;
      }).toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
