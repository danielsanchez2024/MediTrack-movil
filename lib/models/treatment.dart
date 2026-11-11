class Treatment {
  Treatment({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.dosage,
    required this.instructions,
    required this.frequencyValue,
    required this.frequencyUnit,
    required this.active,
    required this.remainingQuantity,
    required this.totalQuantity,
    required this.startDate,
    required this.endDate,
    required this.registrationSource,
    this.quantityPerDose,
  });

  factory Treatment.fromJson(Map<String, dynamic> json) => Treatment(
        id: json['id'] as String,
        medicationId: json['medicationId'] as String?,
        medicationName: json['medicationName'] as String,
        dosage: json['dosage'] as String,
        instructions: json['instructions'] as String?,
        frequencyValue: json['frequencyValue'] as int?,
        frequencyUnit: json['frequencyUnit'] as String?,
        active: json['active'] as bool? ?? true,
        remainingQuantity: json['remainingQuantity'] as int?,
        totalQuantity: json['totalQuantity'] as int?,
        startDate: json['startDate'] != null ? DateTime.parse(json['startDate'] as String).toLocal() : null,
        // A plain calendar date ("2026-10-05"), parsed as local midnight.
        endDate: json['endDate'] != null ? DateTime.parse(json['endDate'] as String) : null,
        registrationSource: json['registrationSource'] as String?,
        quantityPerDose: json['quantityPerDose'] as int?,
      );

  final String id;
  final String? medicationId;
  final String medicationName;
  final String dosage;
  final String? instructions;
  final int? frequencyValue;
  final String? frequencyUnit;
  final bool active;
  final int? remainingQuantity;
  final int? totalQuantity;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? registrationSource;
  final int? quantityPerDose;
}
