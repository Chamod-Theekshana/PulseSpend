import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';

class FeedbackRepository {
  final _dio = DioClient.instance.dio;

  /// Submits a "Report a Problem" / feedback message.
  /// [category] is one of: problem | suggestion | question | other.
  Future<void> submit({
    required String category,
    required String subject,
    required String message,
    String? email,
    String? appVersion,
    String? platform,
  }) async {
    try {
      await _dio.post(ApiConfig.feedback, data: {
        'category': category,
        'subject': subject,
        'message': message,
        if (email != null && email.isNotEmpty) 'email': email,
        'app_version': ?appVersion,
        'platform': ?platform,
      });
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
