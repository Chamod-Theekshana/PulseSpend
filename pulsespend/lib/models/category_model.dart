/// Mirrors `CategoryRow` in CategoryModel.ts.
class CategoryModel {
  final int id;
  final String userId;
  final String name;
  final String type; // 'expense' | 'income' | 'both'
  final DateTime? createdAt;

  const CategoryModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.createdAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      name: json['name'] as String,
      type: (json['type'] as String?) ?? 'expense',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toRequestJson() => {'name': name, 'type': type};
}
