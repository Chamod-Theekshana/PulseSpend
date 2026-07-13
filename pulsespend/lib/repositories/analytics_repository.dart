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

  Future<DigestSummary> getDigest(String range) async {
    try {
      final res = await _dio.get(
        ApiConfig.analyticsDigest,
        queryParameters: {'range': range},
      );
      return DigestSummary.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<List<Insight>> getInsights() async {
    try {
      final res = await _dio.get(ApiConfig.analyticsInsights);
      return (res.data['data'] as List<dynamic>)
          .map((e) => Insight.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
