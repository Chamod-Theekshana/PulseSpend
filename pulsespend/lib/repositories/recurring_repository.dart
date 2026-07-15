import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/page_info.dart';
import '../models/recurring_model.dart';

class RecurringRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<RecurringModel>> list({int limit = 100, int offset = 0}) async {
    try {
      final res = await _dio.get(
        ApiConfig.recurring,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final items = (res.data['recurring'] as List<dynamic>)
          .map((e) => RecurringModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: items, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Subscription-like series detected from real transaction history.
  Future<List<DetectedSubscription>> detected() async {
    try {
      final res = await _dio.get(ApiConfig.recurringDetected);
      return (res.data['detected'] as List<dynamic>)
          .map((e) => DetectedSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Hides a detected subscription series from future detection lists.
  Future<void> dismissDetected(String name) async {
    try {
      await _dio.post(ApiConfig.recurringDetectedDismiss, data: {'name': name});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<RecurringModel> create(RecurringModel rule) async {
    try {
      final res = await _dio.post(ApiConfig.recurring, data: rule.toCreateRequestJson());
      return RecurringModel.fromJson(res.data['recurring'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<RecurringModel> update(int id, RecurringModel rule) async {
    try {
      final res = await _dio.put(ApiConfig.recurringById(id), data: rule.toUpdateRequestJson());
      return RecurringModel.fromJson(res.data['recurring'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<RecurringModel> toggleActive(int id, bool isActive) async {
    try {
      final res = await _dio.put(ApiConfig.recurringById(id), data: {'is_active': isActive});
      return RecurringModel.fromJson(res.data['recurring'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.recurringById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.recurringBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deletedCount'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
