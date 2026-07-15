import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/wallet_model.dart';

class WalletRepository {
  final _dio = DioClient.instance.dio;

  Future<List<WalletModel>> list() async {
    try {
      final res = await _dio.get(ApiConfig.wallets);
      return (res.data['wallets'] as List<dynamic>)
          .map((e) => WalletModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<List<WalletBalance>> balances() async {
    try {
      final res = await _dio.get(ApiConfig.walletBalances);
      return (res.data['balances'] as List<dynamic>)
          .map((e) => WalletBalance.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<NetWorth> netWorth() async {
    try {
      final res = await _dio.get(ApiConfig.walletNetWorth);
      return NetWorth.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Moves money between two wallets (id 0 = the default bucket). The backend
  /// records a −/+ transaction pair that shifts balances but stays out of
  /// income/expense analytics.
  Future<void> transfer({required int fromWalletId, required int toWalletId, required double amount}) async {
    try {
      await _dio.post(ApiConfig.walletTransfer, data: {
        'from_wallet_id': fromWalletId,
        'to_wallet_id': toWalletId,
        'amount': amount,
      });
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<WalletModel> create({required String name, required String type, required String currency}) async {
    try {
      final res = await _dio.post(ApiConfig.wallets, data: {'name': name, 'type': type, 'currency': currency});
      return WalletModel.fromJson(res.data['wallet'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<WalletModel> update(int id, {String? name, String? type, String? currency}) async {
    try {
      final res = await _dio.put(ApiConfig.walletById(id), data: {
        if (name != null) 'name': name,
        if (type != null) 'type': type,
        if (currency != null) 'currency': currency,
      });
      return WalletModel.fromJson(res.data['wallet'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.walletById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
