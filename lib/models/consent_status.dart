class ConsentStatus {
  ConsentStatus({
    required this.requiresAcceptance,
    required this.version,
    required this.contentUrl,
  });

  factory ConsentStatus.fromJson(Map<String, dynamic> json) => ConsentStatus(
        requiresAcceptance: json['requiresAcceptance'] as bool? ?? false,
        version: json['version'] as String? ?? '',
        contentUrl: json['contentUrl'] as String?,
      );

  final bool requiresAcceptance;
  final String version;
  final String? contentUrl;
}
