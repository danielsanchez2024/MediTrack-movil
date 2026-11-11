// A profile the user can view: themselves, or a dependent they manage.
class ProfileSummary {
  ProfileSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.claimed,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) => ProfileSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String?,
        claimed: json['claimed'] as bool? ?? false,
      );

  final String id;
  final String name;
  final String? email;
  // A dependent who claimed their own account: the caregiver then only has
  // access while that person keeps granting it.
  final bool claimed;
}

// A one-time code the caregiver hands to a dependent so they can claim their
// own account. The backend only ever shows it once (it's stored hashed).
class DependentInvite {
  DependentInvite({required this.code, required this.expiresAt});

  factory DependentInvite.fromJson(Map<String, dynamic> json) => DependentInvite(
        code: json['claimToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
      );

  final String code;
  final DateTime expiresAt;
}

class CaregiverAccessStatus {
  CaregiverAccessStatus({required this.hasCaregiver, required this.caregiverName, required this.granted});

  factory CaregiverAccessStatus.fromJson(Map<String, dynamic> json) => CaregiverAccessStatus(
        hasCaregiver: json['hasCaregiver'] as bool? ?? false,
        caregiverName: json['caregiverName'] as String?,
        granted: json['granted'] as bool? ?? false,
      );

  final bool hasCaregiver;
  final String? caregiverName;
  final bool granted;
}
