/// A shared "family" group (backend GroupModel). Members see a combined,
/// read-only view of everyone's transactions plus a merged summary.
class GroupModel {
  final int id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final int memberCount;
  final String role; // 'owner' | 'member'

  const GroupModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    this.memberCount = 1,
    this.role = 'member',
  });

  bool get isOwner => role == 'owner';

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: int.parse(json['id'].toString()),
      name: (json['name'] as String?) ?? '',
      ownerId: json['owner_id'].toString(),
      inviteCode: (json['invite_code'] as String?) ?? '',
      memberCount: (json['member_count'] as num?)?.toInt() ?? 1,
      role: (json['role'] as String?) ?? 'member',
    );
  }
}

class GroupMember {
  final String userId;
  final String? name;
  final String email;
  final String role;

  const GroupMember({required this.userId, required this.name, required this.email, required this.role});

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : email.split('@').first;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'].toString(),
      name: json['name'] as String?,
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'member',
    );
  }
}

class GroupSummary {
  final double income;
  final double expense;
  final double balance;
  final String currency;
  final int transactionCount;

  const GroupSummary({
    required this.income,
    required this.expense,
    required this.balance,
    required this.currency,
    required this.transactionCount,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return GroupSummary(
      income: d(json['income']),
      expense: d(json['expense']),
      balance: d(json['balance']),
      currency: (json['currency'] as String?) ?? 'LKR',
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One row in a group's combined feed — a member's transaction plus who it
/// belongs to.
class GroupTransaction {
  final int id;
  final String memberName;
  final String title;
  final double amount;
  final String currency;
  final String category;
  final DateTime createdAt;
  final String? notes;
  final String? receiptUrl;

  /// What the viewer owes on this shared expense (their frozen split), in the
  /// expense's currency. Null if they aren't a participant.
  final double? viewerOwed;

  const GroupTransaction({
    required this.id,
    required this.memberName,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.createdAt,
    this.notes,
    this.receiptUrl,
    this.viewerOwed,
  });

  bool get isExpense => amount < 0;

  factory GroupTransaction.fromJson(Map<String, dynamic> json) {
    final owed = json['viewer_owed'];
    return GroupTransaction(
      id: int.parse(json['id'].toString()),
      memberName: (json['member_name'] as String?) ?? 'Member',
      title: (json['title'] as String?) ?? '',
      amount: double.parse(json['amount'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      category: (json['category'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'].toString()),
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      viewerOwed: owed == null ? null : double.tryParse(owed.toString()),
    );
  }
}

/// Bundle returned by the group transactions endpoint.
class GroupFeed {
  final List<GroupTransaction> transactions;
  final GroupSummary summary;
  const GroupFeed({required this.transactions, required this.summary});
}

/// One member's Splitwise-lite balance. net > 0 → gets back; net < 0 → owes.
class MemberBalance {
  final String userId;
  final String name;
  final double paid;
  final double owed;
  final double net;

  const MemberBalance({
    required this.userId,
    required this.name,
    required this.paid,
    this.owed = 0,
    required this.net,
  });

  factory MemberBalance.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return MemberBalance(
      userId: json['user_id'].toString(),
      name: (json['name'] as String?) ?? 'Member',
      paid: d(json['paid']),
      owed: d(json['owed']),
      net: d(json['net']),
    );
  }
}

/// A recorded settle-up entry. `status` is pending until the payee confirms;
/// only a confirmed one moves the balances.
class GroupSettlement {
  final int id;
  final String fromName;
  final String toName;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
  final String status; // confirmed (settle-ups are immediate; either party can undo)
  final DateTime createdAt;

  const GroupSettlement({
    required this.id,
    required this.fromName,
    required this.toName,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
  });

  factory GroupSettlement.fromJson(Map<String, dynamic> json) {
    return GroupSettlement(
      id: int.parse(json['id'].toString()),
      fromName: (json['from_name'] as String?) ?? 'Member',
      toName: (json['to_name'] as String?) ?? 'Member',
      fromUserId: json['from_user'].toString(),
      toUserId: json['to_user'].toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?) ?? 'LKR',
      status: (json['status'] as String?) ?? 'confirmed',
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}

/// A suggested repayment ("from pays to X") that zeroes the balances.
class SettleSuggestion {
  final String fromUserId;
  final String fromName;
  final String toUserId;
  final String toName;
  final double amount;

  const SettleSuggestion({
    required this.fromUserId,
    required this.fromName,
    required this.toUserId,
    required this.toName,
    required this.amount,
  });

  factory SettleSuggestion.fromJson(Map<String, dynamic> json) {
    return SettleSuggestion(
      fromUserId: json['from'].toString(),
      fromName: (json['from_name'] as String?) ?? '',
      toUserId: json['to'].toString(),
      toName: (json['to_name'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class GroupBalances {
  final List<MemberBalance> members;
  final List<SettleSuggestion> suggestions;
  final double total;
  final String currency;

  const GroupBalances({
    required this.members,
    required this.suggestions,
    required this.total,
    required this.currency,
  });

  factory GroupBalances.fromJson(Map<String, dynamic> json) {
    return GroupBalances(
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((e) => MemberBalance.fromJson(e as Map<String, dynamic>))
          .toList(),
      suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
          .map((e) => SettleSuggestion.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?) ?? 'LKR',
    );
  }
}
