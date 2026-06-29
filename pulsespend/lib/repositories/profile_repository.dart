import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/user_model.dart';

class ProfileRepository {
  final _dio = DioClient.instance.dio;

  Future<UserModel> getProfile(String userId) async {
    try {
      final res = await _dio.get(ApiConfig.profile(userId));
      return UserModel.fromJson(res.data['profile'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<UserModel> updateProfile(
    String userId, {
    String? name,
    String? firstName,
    String? surname,
    String? dob,
    String? gender,
    String? contactNo,
    String? profilePhoto,
    String? theme,
    String? currency,
    String? dateFormat,
    bool? biometricEnabled,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (firstName != null) body['first_name'] = firstName;
      if (surname != null) body['surname'] = surname;
      if (dob != null) body['date_of_birth'] = dob;
      if (gender != null) body['gender'] = gender;
      if (contactNo != null) body['contact_no'] = contactNo;
      if (profilePhoto != null) body['profile_photo'] = profilePhoto;
      if (theme != null) body['theme'] = theme;
      if (currency != null) body['currency'] = currency;
      if (dateFormat != null) body['date_format'] = dateFormat;
      if (biometricEnabled != null) body['biometric_enabled'] = biometricEnabled;

      final res = await _dio.put(ApiConfig.profile(userId), data: body);
      return UserModel.fromJson(res.data['profile'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> updatePassword(
    String userId, {
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.put(
        ApiConfig.profilePassword(userId),
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Full JSON backup of the user's data (transactions, categories, budgets,
  /// goals, reminders, recurring) — see exportUserData in profileController.ts.
  Future<Map<String, dynamic>> exportData(String userId) async {
    try {
      final res = await _dio.get(ApiConfig.profileDataExport(userId));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Import user data
  Future<void> importData(String userId, Map<String, dynamic> data) async {
    try {
      await _dio.post(ApiConfig.profileDataImport(userId), data: data);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
