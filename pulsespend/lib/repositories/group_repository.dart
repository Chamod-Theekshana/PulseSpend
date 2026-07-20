import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/goal_model.dart';
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

  /// Savings goals shared with this group.
  Future<List<GoalModel>> goals(int groupId) async {
    try {
      final res = await _dio.get(ApiConfig.groupGoals(groupId));
      return (res.data['goals'] as List<dynamic>)
          .map((e) => GoalModel.fromJson(e as Map<String, dynamic>))
          .toList();
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

  /// Records "I paid [toUser] [amount]" — settles immediately and moves real
  /// cash (the payer's [walletId], or the default bucket if null; the payee's
  /// side lands in their default bucket).
  Future<void> settle(int groupId,
      {required String toUser, required double amount, required String currency, int? walletId}) async {
    try {
      await _dio.post(ApiConfig.groupSettle(groupId), data: {
        'to_user': toUser,
        'amount': amount,
        'currency': currency,
        if (walletId != null) 'wallet_id': walletId,
      });
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<List<GroupSettlement>> settlements(int groupId) async {
    try {
      final res = await _dio.get(ApiConfig.groupSettlements(groupId));
      return (res.data['settlements'] as List<dynamic>)
          .map((e) => GroupSettlement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Either party undoes a settle-up: removes it and reverses both cash legs.
  Future<void> undoSettlement(int groupId, int settlementId) async {
    try {
      await _dio.delete(ApiConfig.groupSettlementById(groupId, settlementId));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> rename(int groupId, String name) async {
    try {
      await _dio.put(ApiConfig.groupById(groupId), data: {'name': name});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> transferOwnership(int groupId, String newOwnerId) async {
    try {
      await _dio.put(ApiConfig.groupOwner(groupId), data: {'user_id': newOwnerId});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> removeMember(int groupId, String userId) async {
    try {
      await _dio.delete(ApiConfig.groupMember(groupId, userId));
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }
}
