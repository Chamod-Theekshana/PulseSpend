import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category_model.dart';
import 'repository_providers.dart';

class CategoriesState {
  final List<CategoryModel> items;
  final bool isLoading;
  final String? error;

  const CategoriesState({this.items = const [], this.isLoading = false, this.error});

  CategoriesState copyWith({List<CategoryModel>? items, bool? isLoading, String? error}) {
    return CategoriesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<CategoryModel> get expenseCategories =>
      items.where((c) => c.type == 'expense' || c.type == 'both').toList();
  List<CategoryModel> get incomeCategories =>
      items.where((c) => c.type == 'income' || c.type == 'both').toList();
}

class CategoriesController extends Notifier<CategoriesState> {
  @override
  CategoriesState build() {
    Future.microtask(refresh);
    return const CategoriesState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref.read(categoryRepositoryProvider).list();
      state = state.copyWith(items: result.items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create({required String name, required String type}) async {
    final created = await ref.read(categoryRepositoryProvider).create(name: name, type: type);
    state = state.copyWith(items: [...state.items, created]);
  }

  Future<void> update(int id, {required String name, required String type}) async {
    final updated = await ref.read(categoryRepositoryProvider).update(id, name: name, type: type);
    state = state.copyWith(items: [for (final c in state.items) if (c.id == id) updated else c]);
  }

  Future<void> delete(int id) async {
    await ref.read(categoryRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((c) => c.id != id).toList());
  }
}

final categoriesControllerProvider =
    NotifierProvider<CategoriesController, CategoriesState>(CategoriesController.new);
