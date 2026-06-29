/// Mirrors the `{ limit, offset, total }` page object returned alongside
/// every paginated list endpoint (parsePagination() in validators.ts).
class PageInfo {
  final int limit;
  final int offset;
  final int total;

  const PageInfo({required this.limit, required this.offset, required this.total});

  factory PageInfo.fromJson(Map<String, dynamic> json) {
    return PageInfo(
      limit: int.parse((json['limit'] ?? 50).toString()),
      offset: int.parse((json['offset'] ?? 0).toString()),
      total: int.parse((json['total'] ?? 0).toString()),
    );
  }

  bool get hasMore => offset + limit < total;

  static const empty = PageInfo(limit: 50, offset: 0, total: 0);
}

class PagedResult<T> {
  final List<T> items;
  final PageInfo page;

  const PagedResult({required this.items, required this.page});
}
