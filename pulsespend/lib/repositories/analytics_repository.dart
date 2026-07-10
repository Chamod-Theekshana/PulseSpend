import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/analytics_model.dart';

/// Data access for the analytics summary. Routes through [ApiConfig] and the
/// shared [DioClient] like every other repository, normalising failures to an
/// [ApiException] instead of leaking a raw `Exception('Failed to fetch...')`.
class AnalyticsRepository {
  final _dio = DioClient.instance.dio;

  Future<AnalyticsSummary> getSummary(String period) async {
    try {
      final res = await _dio.get(
        ApiConfig.analytics,
        queryParameters: {'period': period},
      );
      return AnalyticsSummary.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
