import 'treatment.dart';

class EmergencyAllergy {
  EmergencyAllergy({required this.id, required this.description, required this.severity});

  factory EmergencyAllergy.fromJson(Map<String, dynamic> json) => EmergencyAllergy(
        id: json['id'] as String? ?? '',
        description: json['description'] as String,
        severity: json['severity'] as String,
      );

  final String id;
  final String description;
  final String severity;
}

class EmergencyCard {
  EmergencyCard({
    required this.name,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.allergies,
    required this.activeTreatments,
  });

  factory EmergencyCard.fromJson(Map<String, dynamic> json) => EmergencyCard(
        name: json['name'] as String,
        emergencyContactName: json['emergencyContactName'] as String?,
        emergencyContactPhone: json['emergencyContactPhone'] as String?,
        allergies: (json['allergies'] as List? ?? [])
            .map((e) => EmergencyAllergy.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeTreatments: (json['activeTreatments'] as List? ?? [])
            .map((e) => Treatment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String name;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final List<EmergencyAllergy> allergies;
  final List<Treatment> activeTreatments;
}

// In the order the severity picker offers them.
const allergySeverityLabels = {
  'MILD': 'Leve',
  'MODERATE': 'Moderada',
  'SEVERE': 'Severa',
};
