import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/goal_model.dart';
import '../models/page_info.dart';

class GoalRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<GoalModel>> list({int limit = 100, int offset = 0}) async {
    try {
      final res = await _dio.get(ApiConfig.goals, queryParameters: {'limit': limit, 'offset': offset});
      final items = (res.data['goals'] as List<dynamic>)
          .map((e) => GoalModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: items, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GoalModel> create(GoalModel goal) async {
    try {
      final res = await _dio.post(ApiConfig.goals, data: goal.toRequestJson());
      return GoalModel.fromJson(res.data['goal'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GoalModel> update(int id, GoalModel goal) async {
    try {
      final res = await _dio.put(ApiConfig.goalById(id), data: goal.toRequestJson());
      return GoalModel.fromJson(res.data['goal'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// `conversion_warning` (string) may come back in the response if the
  /// contribution currency differs from the goal's and the live FX rate
  /// lookup failed — surfaced to the UI as a non-fatal warning banner.
  Future<({GoalModel goal, String? warning})> contribute({
    required int id,
    required double amount,
    required String currency,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.goalContribute(id),
        data: {'amount': amount, 'currency': currency},
      );
      final goal = GoalModel.fromJson(res.data['goal'] as Map<String, dynamic>);
      return (goal: goal, warning: res.data['conversion_warning'] as String?);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.goalById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.goalsBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deletedCount'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
