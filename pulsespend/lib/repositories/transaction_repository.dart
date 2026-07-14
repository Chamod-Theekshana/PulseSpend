import 'package:dio/dio.dart';
import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/page_info.dart';
import '../models/transaction_model.dart';
import '../providers/transactions_provider.dart';

class TransactionRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<TransactionModel>> list({
    required String userId,
    int limit = 50,
    int offset = 0,
    TransactionFilters? filters,
  }) async {
    try {
      final res = await _dio.get(
        ApiConfig.transactionsByUser(userId),
        queryParameters: {
          'limit': limit,
          'offset': offset,
          ...?filters?.toQueryParams(),
        },
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

  /// Fetches the server-generated CSV of transactions matching [filters] (or
  /// everything when null). Returns the raw CSV text for the caller to save
  /// and share.
  Future<String> exportCsv({
    required String userId,
    TransactionFilters? filters,
  }) async {
    try {
      final res = await _dio.get<String>(
        ApiConfig.transactionExportCsv(userId),
        queryParameters: filters?.toQueryParams(),
        options: Options(responseType: ResponseType.plain),
      );
      return res.data ?? '';
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

  /// Posts a pre-built request body (used by the offline outbox, which stores
  /// the exact body — including the `client_op_id` idempotency key — so a
  /// replay after reconnect is byte-for-byte the original request).
  Future<TransactionModel> createRaw(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(ApiConfig.transactions, data: body);
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

  /// Bulk CSV import. Each row: title, amount, category, created_at (yyyy-MM-dd),
  /// currency?, client_op_id (dedupes re-imports server-side). Returns counts.
  Future<({int imported, int duplicates, int skipped})> bulkImport(
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final res = await _dio.post(ApiConfig.transactionsBulkImport, data: {'rows': rows});
      int n(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;
      return (
        imported: n(res.data['imported']),
        duplicates: n(res.data['duplicates']),
        skipped: n(res.data['skipped']),
      );
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
