// One medication the backend read off a prescription photo. Any field it couldn't make out
// is null — never guessed — and the review form makes the user fill it in.
class ScannedMedication {
  ScannedMedication({
    required this.medicationName,
    required this.dosage,
    required this.frequencyHours,
    required this.durationDays,
  });

  factory ScannedMedication.fromJson(Map<String, dynamic> json) => ScannedMedication(
        medicationName: _blankToNull(json['medicationName'] as String?),
        dosage: _blankToNull(json['dosage'] as String?),
        frequencyHours: json['frequencyHours'] as int?,
        durationDays: json['durationDays'] as int?,
      );

  final String? medicationName;
  final String? dosage;
  final int? frequencyHours;
  final int? durationDays;

  // What the user still has to complete by hand, in the order the form asks for it.
  List<String> get missingFields => [
        if (medicationName == null) 'nombre',
        if (dosage == null) 'cantidad a tomar',
        if (frequencyHours == null) 'frecuencia',
        if (durationDays == null) 'duración',
      ];

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
