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

  const GroupTransaction({
    required this.id,
    required this.memberName,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.createdAt,
  });

  bool get isExpense => amount < 0;

  factory GroupTransaction.fromJson(Map<String, dynamic> json) {
    return GroupTransaction(
      id: int.parse(json['id'].toString()),
      memberName: (json['member_name'] as String?) ?? 'Member',
      title: (json['title'] as String?) ?? '',
      amount: double.parse(json['amount'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      category: (json['category'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}

/// Bundle returned by the group transactions endpoint.
class GroupFeed {
  final List<GroupTransaction> transactions;
  final GroupSummary summary;
  const GroupFeed({required this.transactions, required this.summary});
}
