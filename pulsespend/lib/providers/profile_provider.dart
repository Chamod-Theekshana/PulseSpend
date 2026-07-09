import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

class ProfileState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const ProfileState({this.user, this.isLoading = false, this.error});

  ProfileState copyWith({UserModel? user, bool? isLoading, String? error}) {
    return ProfileState(user: user ?? this.user, isLoading: isLoading ?? this.isLoading, error: error);
  }

  String get currency => user?.currency ?? 'USD';
  String get dateFormatPattern => user?.dateFormat ?? 'DD/MM/YYYY';
  String get language => user?.language ?? 'English';
}

class ProfileController extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.userId != next.userId && next.userId != null) {
        refresh();
      }
    });

    SocketService.instance.on('profile:updated', (data) {
      if (data is Map<String, dynamic> && data['profile'] != null) {
        state = state.copyWith(user: UserModel.fromJson(data['profile'] as Map<String, dynamic>));
      }
    });

    try {
      final userId = ref.read(currentUserIdProvider);
      Future.microtask(refresh);
    } catch (_) {
      // Ignore: will be triggered by the listener once authenticated
    }

    return const ProfileState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = ref.read(currentUserIdProvider);
      final user = await ref.read(profileRepositoryProvider).getProfile(userId);
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> update({
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
    String? language,
    bool? biometricEnabled,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    final updated = await ref.read(profileRepositoryProvider).updateProfile(
          userId,
          name: name,
          firstName: firstName,
          surname: surname,
          dob: dob,
          gender: gender,
          contactNo: contactNo,
          profilePhoto: profilePhoto,
          theme: theme,
          currency: currency,
          dateFormat: dateFormat,
          language: language,
          biometricEnabled: biometricEnabled,
        );
    state = state.copyWith(user: updated);
  }

  Future<void> importData(Map<String, dynamic> data) async {
    final userId = ref.read(currentUserIdProvider);
    await ref.read(profileRepositoryProvider).importData(userId, data);
    await refresh(); // Refresh all data if necessary, or just profile
  }

  Future<void> updatePassword({required String currentPassword, required String newPassword}) async {
    final userId = ref.read(currentUserIdProvider);
    await ref
        .read(profileRepositoryProvider)
        .updatePassword(userId, currentPassword: currentPassword, newPassword: newPassword);
  }
}

final profileControllerProvider = NotifierProvider<ProfileController, ProfileState>(ProfileController.new);
