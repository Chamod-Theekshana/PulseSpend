import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/notification_model.dart';
import '../models/notification_preferences_model.dart';

class NotificationRepository {
  final _dio = DioClient.instance.dio;

  Future<({List<NotificationModel> items, int unreadCount})> history({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _dio.get(
        ApiConfig.notificationHistory,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final items = (res.data['notifications'] as List<dynamic>)
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final unread = int.parse((res.data['unreadCount'] ?? 0).toString());
      return (items: items, unreadCount: unread);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.patch(ApiConfig.notificationMarkAllRead);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> markOneRead(int id) async {
    try {
      await _dio.patch(ApiConfig.notificationMarkOneRead(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> clear() async {
    try {
      await _dio.delete(ApiConfig.notificationClear);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> saveFcmToken(String fcmToken) async {
    try {
      await _dio.post(ApiConfig.notificationSaveToken, data: {'fcm_token': fcmToken});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<NotificationPreferences> getPreferences() async {
    try {
      final res = await _dio.get(ApiConfig.notificationPreferences);
      return NotificationPreferences.fromJson(res.data['preferences'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<NotificationPreferences> updatePreferences(Map<String, bool> updates) async {
    try {
      final res = await _dio.put(ApiConfig.notificationPreferences, data: updates);
      return NotificationPreferences.fromJson(res.data['preferences'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
