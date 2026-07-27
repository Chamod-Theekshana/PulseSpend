/// Mirrors `UserModel.ts`'s `User` interface (minus `password`, which the
/// backend always strips before returning via `getProfile`/`updateProfile`).
class UserModel {
  final int id;
  final String email;
  final String? name;
  final String? profilePhoto;
  final String theme; // 'dark' | 'light' | 'system'
  final String currency;
  final String dateFormat; // 'DD/MM/YYYY' | 'MM/DD/YYYY' | 'YYYY-MM-DD'
  final String language;
  final String? firstName;
  final String? surname;
  final DateTime? dob;
  final String? gender;
  final String? contactNo;
  final bool biometricEnabled;
  final DateTime? createdAt;

  /// Round-up savings rule (null = off): expenses round up to [roundupTo] and
  /// the spare change auto-contributes to goal [roundupGoalId].
  final int? roundupGoalId;
  final int? roundupTo;
  /// Wallet the spare change is debited from (0 = default bucket). Null pauses
  /// round-ups — a contribution has to come from somewhere.
  final int? roundupWalletId;

  /// Set while the account is inside its 7-day deletion grace window; the app
  /// offers a "Restore account" banner until it is cancelled or purged.
  final DateTime? deletionRequestedAt;

  const UserModel({
    required this.id,
    required this.email,
    this.name,
    this.profilePhoto,
    this.theme = 'system',
    this.currency = 'USD',
    this.dateFormat = 'DD/MM/YYYY',
    this.language = 'English',
    this.firstName,
    this.surname,
    this.dob,
    this.gender,
    this.contactNo,
    this.biometricEnabled = false,
    this.createdAt,
    this.roundupGoalId,
    this.roundupTo,
    this.roundupWalletId,
    this.deletionRequestedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: int.parse(json['id'].toString()),
      email: json['email'] as String,
      name: json['name'] as String?,
      profilePhoto: json['profile_photo'] as String?,
      theme: (json['theme'] as String?) ?? 'system',
      currency: (json['currency'] as String?) ?? 'USD',
      dateFormat: (json['date_format'] as String?) ?? 'DD/MM/YYYY',
      language: (json['language'] as String?) ?? 'English',
      firstName: json['first_name'] as String?,
      surname: json['surname'] as String?,
      dob: json['date_of_birth'] != null ? DateTime.tryParse(json['date_of_birth'].toString()) : null,
      gender: json['gender'] as String?,
      contactNo: json['contact_no'] as String?,
      biometricEnabled: json['biometric_enabled'] == true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      roundupGoalId:
          json['roundup_goal_id'] != null ? int.tryParse(json['roundup_goal_id'].toString()) : null,
      roundupTo: json['roundup_to'] != null ? int.tryParse(json['roundup_to'].toString()) : null,
      roundupWalletId: json['roundup_wallet_id'] != null
          ? int.tryParse(json['roundup_wallet_id'].toString())
          : null,
      deletionRequestedAt: json['deletion_requested_at'] != null
          ? DateTime.tryParse(json['deletion_requested_at'].toString())
          : null,
    );
  }

  String get fullName {
    if (firstName != null && firstName!.isNotEmpty && surname != null && surname!.isNotEmpty) {
      return '$firstName $surname';
    } else if (firstName != null && firstName!.isNotEmpty) {
      return firstName!;
    } else if (surname != null && surname!.isNotEmpty) {
      return surname!;
    } else if (name != null && name!.isNotEmpty) {
      return name!;
    }
    return email.split('@').first;
  }

  UserModel copyWith({
    String? name,
    String? profilePhoto,
    String? theme,
    String? currency,
    String? dateFormat,
    String? language,
    String? firstName,
    String? surname,
    DateTime? dob,
    String? gender,
    String? contactNo,
    bool? biometricEnabled,
  }) {
    return UserModel(
      id: id,
      email: email,
      name: name ?? this.name,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      theme: theme ?? this.theme,
      currency: currency ?? this.currency,
      dateFormat: dateFormat ?? this.dateFormat,
      language: language ?? this.language,
      firstName: firstName ?? this.firstName,
      surname: surname ?? this.surname,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      contactNo: contactNo ?? this.contactNo,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      createdAt: createdAt,
      roundupGoalId: roundupGoalId,
      roundupWalletId: roundupWalletId,
      roundupTo: roundupTo,
      deletionRequestedAt: deletionRequestedAt,
    );
  }
}
