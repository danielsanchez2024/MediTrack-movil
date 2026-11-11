class AdherenceSummary {
  AdherenceSummary({
    required this.total,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.pending,
    required this.percentage,
  });

  factory AdherenceSummary.fromJson(Map<String, dynamic> json) => AdherenceSummary(
        total: json['total'] as int,
        taken: json['taken'] as int,
        skipped: json['skipped'] as int,
        missed: json['missed'] as int,
        pending: json['pending'] as int,
        percentage: json['percentage'] as int,
      );

  final int total;
  final int taken;
  final int skipped;
  final int missed;
  final int pending;
  final int percentage;
}
