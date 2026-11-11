class UserProfile {
  UserProfile({required this.name, required this.email});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String,
        email: json['email'] as String? ?? '',
      );

  final String name;
  final String email;
}
