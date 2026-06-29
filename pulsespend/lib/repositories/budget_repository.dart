import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/budget_model.dart';
import '../models/page_info.dart';

class BudgetRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<BudgetModel>> list({int limit = 100, int offset = 0}) async {
    try {
      final res = await _dio.get(
        ApiConfig.budgets,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final items = (res.data['budgets'] as List<dynamic>)
          .map((e) => BudgetModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: items, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Enriched list with spent/percentage/remaining for a given period.
  /// Defaults to the current month when no args are passed.
  Future<List<BudgetModel>> status({int? year, int? month, int? day}) async {
    try {
      final res = await _dio.get(
        ApiConfig.budgetStatus,
        queryParameters: {
          if (year != null) 'year': year,
          if (month != null) 'month': month,
          if (day != null) 'day': day,
        },
      );
      return (res.data['budgets'] as List<dynamic>)
          .map((e) => BudgetModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<BudgetModel> create(BudgetModel budget) async {
    try {
      final res = await _dio.post(ApiConfig.budgets, data: budget.toCreateRequestJson());
      return BudgetModel.fromJson(res.data['budget'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<BudgetModel> updateAmount(int id, double amount) async {
    try {
      final res = await _dio.put(ApiConfig.budgetById(id), data: {'amount': amount});
      return BudgetModel.fromJson(res.data['budget'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.budgetById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.budgetsBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deletedCount'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
