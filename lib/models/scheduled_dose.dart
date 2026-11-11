enum DoseStatus { pending, taken, skipped, missed, unknown }

DoseStatus doseStatusFromJson(String value) {
  switch (value) {
    case 'PENDING':
      return DoseStatus.pending;
    case 'TAKEN':
      return DoseStatus.taken;
    case 'SKIPPED':
      return DoseStatus.skipped;
    case 'MISSED':
      return DoseStatus.missed;
    default:
      return DoseStatus.unknown;
  }
}

String doseStatusToJson(DoseStatus status) {
  switch (status) {
    case DoseStatus.pending:
      return 'PENDING';
    case DoseStatus.taken:
      return 'TAKEN';
    case DoseStatus.skipped:
      return 'SKIPPED';
    case DoseStatus.missed:
      return 'MISSED';
    case DoseStatus.unknown:
      return 'PENDING';
  }
}

class ScheduledDose {
  ScheduledDose({
    required this.id,
    required this.medicationName,
    required this.dosage,
    required this.instructions,
    required this.scheduledAt,
    required this.status,
    required this.recordedAt,
    required this.notes,
    required this.recordedByName,
    required this.withinWindow,
    required this.recordable,
    this.correctable = false,
    this.remainingQuantity,
    this.treatmentId,
  });

  factory ScheduledDose.fromJson(Map<String, dynamic> json) => ScheduledDose(
        id: json['id'] as String,
        medicationName: json['medicationName'] as String,
        dosage: json['dosage'] as String,
        instructions: json['instructions'] as String?,
        // The API sends instants with their offset ("…T08:00:00-05:00"); toLocal()
        // turns them into this phone's wall-clock time, which is what the rest of
        // the app (grouping, formatting, reminders) works in.
        scheduledAt: DateTime.parse(json['scheduledAt'] as String).toLocal(),
        status: doseStatusFromJson(json['status'] as String),
        recordedAt: json['recordedAt'] != null
            ? DateTime.parse(json['recordedAt'] as String).toLocal()
            : null,
        notes: json['notes'] as String?,
        recordedByName: json['recordedByName'] as String?,
        withinWindow: json['withinWindow'] as bool? ?? true,
        recordable: json['recordable'] as bool? ?? false,
        correctable: json['correctable'] as bool? ?? false,
        remainingQuantity: json['remainingQuantity'] as int?,
        treatmentId: json['treatmentId'] as String?,
      );

  final String id;
  final String medicationName;
  final String dosage;
  final String? instructions;
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime? recordedAt;
  final String? notes;
  final String? recordedByName;
  final bool withinWindow;
  final bool recordable;

  // Mirrors the backend's EARLY_RECORDING_BUFFER_MINUTES (ScheduledDoseMapper /
  // ScheduledDoseService): a pending dose can be recorded from 10 minutes before it's due.
  static const earlyRecordingBuffer = Duration(minutes: 10);

  DateTime get recordableFrom => scheduledAt.subtract(earlyRecordingBuffer);

  // `recordable` is a snapshot from when the list was fetched; this re-evaluates it against
  // the screen's clock so a dose "coming up" unlocks on its own, without a pull-to-refresh.
  bool isRecordableAt(DateTime now) => recordable || !now.isBefore(recordableFrom);
  // Whether the backend would still accept a correction: always for MISSED, and
  // for TAKEN/SKIPPED only within 15 minutes of being recorded.
  final bool correctable;
  // Units left in this treatment's supply; null when it isn't tracked.
  final int? remainingQuantity;
  final String? treatmentId;
}
