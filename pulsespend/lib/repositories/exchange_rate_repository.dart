import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';

class ExchangeRateRepository {
  final _dio = DioClient.instance.dio;

  Future<Map<String, double>> getAllRates(String base) async {
    try {
      final res = await _dio.get(ApiConfig.exchangeRates, queryParameters: {'base': base});
      final rates = res.data['rates'] as Map<String, dynamic>;
      return rates.map((k, v) => MapEntry(k, double.parse(v.toString())));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<double> convert({required double amount, required String from, required String to}) async {
    try {
      final res = await _dio.get(
        ApiConfig.exchangeRatesConvert,
        queryParameters: {'from': from, 'to': to, 'amount': amount},
      );
      return double.parse(res.data['converted'].toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
