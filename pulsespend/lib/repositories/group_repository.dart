import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/group_model.dart';

class GroupRepository {
  final _dio = DioClient.instance.dio;

  Future<List<GroupModel>> list() async {
    try {
      final res = await _dio.get(ApiConfig.groups);
      return (res.data['groups'] as List<dynamic>)
          .map((e) => GroupModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GroupModel> create(String name) async {
    try {
      final res = await _dio.post(ApiConfig.groups, data: {'name': name});
      return GroupModel.fromJson(res.data['group'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GroupModel> join(String inviteCode) async {
    try {
      final res = await _dio.post(ApiConfig.groupJoin, data: {'invite_code': inviteCode});
      return GroupModel.fromJson(res.data['group'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<List<GroupMember>> members(int groupId) async {
    try {
      final res = await _dio.get(ApiConfig.groupMembers(groupId));
      return (res.data['members'] as List<dynamic>)
          .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GroupFeed> feed(int groupId) async {
    try {
      final res = await _dio.get(ApiConfig.groupTransactions(groupId));
      final txs = (res.data['transactions'] as List<dynamic>)
          .map((e) => GroupTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
      final summary = GroupSummary.fromJson(res.data['summary'] as Map<String, dynamic>);
      return GroupFeed(transactions: txs, summary: summary);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> leave(int groupId) async {
    try {
      await _dio.delete(ApiConfig.groupLeave(groupId));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<GroupBalances> balances(int groupId) async {
    try {
      final res = await _dio.get(ApiConfig.groupBalances(groupId));
      return GroupBalances.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Records "I paid [toUser] [amount]" in the group's ledger.
  Future<void> settle(int groupId, {required String toUser, required double amount, required String currency}) async {
    try {
      await _dio.post(ApiConfig.groupSettle(groupId), data: {
        'to_user': toUser,
        'amount': amount,
        'currency': currency,
      });
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
