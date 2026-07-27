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

  /// Month-end money on hand for the dashboard chart — same basis as the
  /// headline, so the last point equals it.
  Future<List<BalanceHistoryPoint>> balanceHistory({int months = 6}) async {
    try {
      final res = await _dio.get(ApiConfig.walletBalanceHistory, queryParameters: {'months': months});
      return (res.data['points'] as List<dynamic>)
          .map((e) => BalanceHistoryPoint.fromJson(e as Map<String, dynamic>))
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

  /// [openingBalance] is a positive magnitude — the backend signs it by wallet
  /// type (liabilities seed negative = the debt owed) and records it as a
  /// transfer-excluded transaction, so it never counts as income/expense.
  ///
  /// [drawdownWalletId] says where a new loan's cash landed. With it, the debt
  /// and the money are recorded together (net-worth-neutral) and the user spends
  /// from that wallet. Without it the debt stands alone — money already spent.
  Future<WalletModel> create({
    required String name,
    required String type,
    required String currency,
    double? openingBalance,
    int? drawdownWalletId,
    double? creditLimit,
  }) async {
    try {
      final res = await _dio.post(ApiConfig.wallets, data: {
        'name': name,
        'type': type,
        'currency': currency,
        if (openingBalance != null && openingBalance > 0) 'opening_balance': openingBalance,
        if (drawdownWalletId != null && (openingBalance ?? 0) > 0)
          'drawdown_wallet_id': drawdownWalletId,
        if (creditLimit != null && creditLimit > 0) 'credit_limit': creditLimit,
      });
      return WalletModel.fromJson(res.data['wallet'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// [setCreditLimit] distinguishes "leave unchanged" (false) from "set/clear
  /// to [creditLimit]" (true, where null clears).
  Future<WalletModel> update(
    int id, {
    String? name,
    String? type,
    String? currency,
    bool setCreditLimit = false,
    double? creditLimit,
  }) async {
    try {
      final res = await _dio.put(ApiConfig.walletById(id), data: {
        if (name != null) 'name': name,
        if (type != null) 'type': type,
        if (currency != null) 'currency': currency,
        if (setCreditLimit) 'credit_limit': creditLimit,
      });
      return WalletModel.fromJson(res.data['wallet'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Corrects what the wallet held (or owed) when it was created. The old seed
  /// is replaced, so the wallet's balance moves — this rewrites transactions,
  /// which is why it isn't part of [update].
  Future<WalletModel> correctOpeningBalance(
    int id, {
    required double openingBalance,
    int? drawdownWalletId,
  }) async {
    try {
      final res = await _dio.put(ApiConfig.walletOpeningBalance(id), data: {
        'opening_balance': openingBalance,
        if (drawdownWalletId != null && openingBalance > 0) 'drawdown_wallet_id': drawdownWalletId,
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
