import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/scheduled_dose.dart';
import 'package:meditrack_mobile/models/treatment.dart';
import 'package:meditrack_mobile/services/dose_reminders.dart';

// run-tests.sh runs the suite under UTC, Europe/Madrid and America/Bogota: whatever the
// phone's zone, a dose the backend schedules for 08:00 Bogotá is the same instant.
void main() {
  final bogota8am = DateTime.utc(2026, 9, 30, 13, 0); // 08:00 at UTC-5

  ScheduledDose parseDose(String scheduledAt) => ScheduledDose.fromJson({
        'id': 'd1',
        'medicationName': 'Losartán',
        'dosage': '1 tableta',
        'scheduledAt': scheduledAt,
        'status': 'PENDING',
        'recordedAt': '2026-09-30T08:02:00-05:00',
      });

  test('offset timestamps become the same instant, in local time', () {
    final dose = parseDose('2026-09-30T08:00:00-05:00');

    expect(dose.scheduledAt.isAtSameMomentAs(bogota8am), isTrue);
    expect(dose.scheduledAt.isUtc, isFalse);
    expect(dose.scheduledAt, bogota8am.toLocal());
    expect(dose.recordedAt!.difference(dose.scheduledAt), const Duration(minutes: 2));
  });

  test('a treatment start date is converted, its end date stays a calendar date', () {
    final t = Treatment.fromJson({
      'id': 't1',
      'medicationName': 'Losartán',
      'dosage': '1 tableta',
      'startDate': '2026-09-30T08:00:00-05:00',
      'endDate': '2026-10-05',
    });

    expect(t.startDate!.isAtSameMomentAs(bogota8am), isTrue);
    expect(t.endDate, DateTime(2026, 10, 5));
  });

  test('reminders fire at the right instant in any zone', () {
    final dose = parseDose('2026-09-30T08:00:00-05:00');
    final reminders = planReminders([dose], DateTime.utc(2026, 9, 30, 12, 0).toLocal());

    expect(reminders.single.at.isAtSameMomentAs(bogota8am), isTrue);
  });
}
