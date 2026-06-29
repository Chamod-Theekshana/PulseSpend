import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/category_model.dart';
import '../models/page_info.dart';

class CategoryRepository {
  final _dio = DioClient.instance.dio;

  Future<PagedResult<CategoryModel>> list({int limit = 100, int offset = 0}) async {
    try {
      final res = await _dio.get(
        ApiConfig.categories,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final items = (res.data['categories'] as List<dynamic>)
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final page = PageInfo.fromJson(res.data['page'] as Map<String, dynamic>);
      return PagedResult(items: items, page: page);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<CategoryModel> create({required String name, String type = 'expense'}) async {
    try {
      final res = await _dio.post(ApiConfig.categories, data: {'name': name, 'type': type});
      return CategoryModel.fromJson(res.data['category'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<CategoryModel> update(int id, {required String name, required String type}) async {
    try {
      final res = await _dio.put(ApiConfig.categoryById(id), data: {'name': name, 'type': type});
      return CategoryModel.fromJson(res.data['category'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete(ApiConfig.categoryById(id));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<int> bulkDelete(List<int> ids) async {
    try {
      final res = await _dio.post(ApiConfig.categoriesBulkDelete, data: {'ids': ids});
      return int.parse((res.data['deletedCount'] ?? 0).toString());
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
