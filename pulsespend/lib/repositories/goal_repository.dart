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
    int? walletId,
    bool spend = false,
    String? category,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.goalContribute(id),
        data: {
          'amount': amount,
          'currency': currency,
          // Only send wallet_id when funding from a wallet; omitting it keeps
          // the contribution a pure counter (no money movement).
          if (walletId != null) 'wallet_id': walletId,
          // spend = withdraw and record as a real expense (not returned to a wallet).
          if (spend) 'spend': true,
          if (spend && category != null) 'category': category,
        },
      );
      final goal = GoalModel.fromJson(res.data['goal'] as Map<String, dynamic>);
      return (goal: goal, warning: res.data['conversion_warning'] as String?);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Sets (amount+day) or clears (nulls) the monthly auto-contribution rule.
  Future<GoalModel> setAutoRule(int id, {double? amount, int? day, int? walletId}) async {
    try {
      final res = await _dio.put(
        ApiConfig.goalAutoRule(id),
        data: {'auto_amount': amount, 'auto_day': day, 'auto_wallet_id': walletId},
      );
      return GoalModel.fromJson(res.data['goal'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Deposit/withdrawal timeline for a goal, newest first.
  Future<List<GoalContribution>> contributions(int id) async {
    try {
      final res = await _dio.get(ApiConfig.goalContributions(id));
      return (res.data['contributions'] as List<dynamic>)
          .map((e) => GoalContribution.fromJson(e as Map<String, dynamic>))
          .toList();
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
