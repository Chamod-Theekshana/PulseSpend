import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/page_info.dart';
import '../models/transaction_model.dart';

class TransactionRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<TransactionModel>> list({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _dio.get(
        ApiConfig.transactionsByUser(userId),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final list = (res.data['transactions'] as List<dynamic>)
          .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: list, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<TransactionSummary> summary(String userId) async {
    try {
      final res = await _dio.get(ApiConfig.transactionSummary(userId));
      return TransactionSummary.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<TransactionModel> getById(String id) async {
    try {
      final res = await _dio.get(ApiConfig.transactionById(id));
      return TransactionModel.fromJson(res.data['transaction'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<TransactionModel> create(TransactionModel transaction) async {
    try {
      final res = await _dio.post(ApiConfig.transactions, data: transaction.toRequestJson());
      return TransactionModel.fromJson(res.data['transaction'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<TransactionModel> update(int id, TransactionModel transaction) async {
    try {
      final res = await _dio.put(
        ApiConfig.transactionUpdate(id.toString()),
        data: transaction.toRequestJson(),
      );
      return TransactionModel.fromJson(res.data['transaction'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.transactionDelete(id.toString()));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.transactionsBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deleted'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
