/// Mirrors the backend `debts` row (DebtModel.ts) — a lightweight 1:1 IOU.
class DebtModel {
  final int id;
  final String counterpartyName;
  final double amount;
  final String currency;
  final String direction; // 'owed_to_me' | 'i_owe'
  final String? note;
  final String status; // 'open' | 'settled'
  final DateTime? createdAt;
  final DateTime? settledAt;

  const DebtModel({
    required this.id,
    required this.counterpartyName,
    required this.amount,
    required this.currency,
    required this.direction,
    this.note,
    this.status = 'open',
    this.createdAt,
    this.settledAt,
  });

  bool get owedToMe => direction == 'owed_to_me';
  bool get isOpen => status == 'open';

  factory DebtModel.fromJson(Map<String, dynamic> json) {
    return DebtModel(
      id: int.parse(json['id'].toString()),
      counterpartyName: (json['counterparty_name'] as String?) ?? '',
      amount: double.parse(json['amount'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      direction: (json['direction'] as String?) ?? 'owed_to_me',
      note: json['note'] as String?,
      status: (json['status'] as String?) ?? 'open',
      createdAt:
          json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      settledAt:
          json['settled_at'] != null ? DateTime.tryParse(json['settled_at'].toString()) : null,
    );
  }

  /// Round-trip serialization for the offline read cache.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'counterparty_name': counterpartyName,
        'amount': amount,
        'currency': currency,
        'direction': direction,
        'note': note,
        'status': status,
        'created_at': createdAt?.toIso8601String(),
        'settled_at': settledAt?.toIso8601String(),
      };
}
