import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/debt_model.dart';

class DebtRepository {
  final _dio = DioClient.instance.dio;

  Future<List<DebtModel>> list() async {
    try {
      final res = await _dio.get(ApiConfig.debts);
      return (res.data['debts'] as List<dynamic>)
          .map((e) => DebtModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Pre-built body create — the outbox replays this exact payload (with its
  /// `client_op_id`), so offline creates are exactly-once.
  Future<DebtModel> createRaw(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(ApiConfig.debts, data: body);
      return DebtModel.fromJson(res.data['debt'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Settling is idempotent server-side, so an offline replay is safe.
  /// [walletId] is where the repayment landed (owed-to-me) or left from
  /// (i-owe); the backend records it as a transfer-excluded movement, so
  /// Earnings/Spendings never move. Null = the cash isn't tracked.
  Future<DebtModel> settle(int id, {int? walletId}) async {
    try {
      final res = await _dio.put(ApiConfig.debtSettle(id), data: {
        if (walletId != null) 'wallet_id': walletId,
      });
      return DebtModel.fromJson(res.data['debt'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.debtById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
