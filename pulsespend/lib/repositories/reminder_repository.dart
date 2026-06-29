import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/page_info.dart';
import '../models/reminder_model.dart';

class ReminderRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<ReminderModel>> list({int limit = 100, int offset = 0}) async {
    try {
      final res = await _dio.get(
        ApiConfig.reminders,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final items = (res.data['reminders'] as List<dynamic>)
          .map((e) => ReminderModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: items, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<ReminderModel> create(ReminderModel reminder) async {
    try {
      final res = await _dio.post(ApiConfig.reminders, data: reminder.toRequestJson());
      return ReminderModel.fromJson(res.data['reminder'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<ReminderModel> update(int id, ReminderModel reminder) async {
    try {
      final res = await _dio.put(ApiConfig.reminderById(id), data: reminder.toRequestJson());
      return ReminderModel.fromJson(res.data['reminder'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.reminderById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.remindersBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deletedCount'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
