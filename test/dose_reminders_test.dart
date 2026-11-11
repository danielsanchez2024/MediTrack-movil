import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/scheduled_dose.dart';
import 'package:meditrack_mobile/models/treatment.dart';
import 'package:meditrack_mobile/services/dose_reminders.dart';

ScheduledDose dose(String name, DateTime at,
        {DoseStatus status = DoseStatus.pending, String? treatmentId}) =>
    ScheduledDose(
      id: '$name-$at',
      treatmentId: treatmentId,
      medicationName: name,
      dosage: '1 tableta',
      instructions: null,
      scheduledAt: at,
      status: status,
      recordedAt: null,
      notes: null,
      recordedByName: null,
      withinWindow: true,
      recordable: false,
    );

void main() {
  final now = DateTime(2026, 9, 30, 10, 0);

  test('only future pending doses get a reminder', () {
    final reminders = planReminders([
      dose('Pasada', now.subtract(const Duration(minutes: 5))),
      dose('Tomada', now.add(const Duration(hours: 1)), status: DoseStatus.taken),
      dose('Omitida', now.add(const Duration(hours: 1)), status: DoseStatus.skipped),
      dose('Losartán', now.add(const Duration(hours: 2))),
    ], now);

    expect(reminders, hasLength(1));
    expect(reminders.single.body, 'Losartán — 1 tableta');
    expect(reminders.single.at, DateTime(2026, 9, 30, 12, 0));
  });

  test('doses due the same minute share one reminder, in time order', () {
    final at = DateTime(2026, 9, 30, 20, 0);
    final reminders = planReminders([
      dose('Metformina', at.add(const Duration(seconds: 30))),
      dose('Aspirina', DateTime(2026, 9, 30, 14, 0)),
      dose('Losartán', at),
    ], now);

    expect(reminders.map((r) => r.body), ['Aspirina — 1 tableta', 'Metformina, Losartán']);
  });

  test('ids are stable for the same slot and unique across slots', () {
    final a = planReminders([dose('A', DateTime(2026, 9, 30, 14, 0))], now).single.id;
    final again = planReminders([dose('B', DateTime(2026, 9, 30, 14, 0, 45))], now).single.id;
    final other = planReminders([dose('A', DateTime(2026, 9, 30, 14, 1))], now).single.id;

    expect(again, a);
    expect(other, isNot(a));
    expect(a, greaterThanOrEqualTo(0));
  });

  test('the payload names the profile, the minute and the real doses', () {
    final at = DateTime(2026, 9, 30, 14, 0);
    final reminder = planReminders([dose('A', at), dose('B', at)], now, profileId: 'dep-1').single;
    final decoded = ReminderPayload.tryParse(reminder.payload.encode())!;

    expect(decoded.profileId, 'dep-1');
    expect(decoded.at, at);
    expect(decoded.doseIds, ['A-$at', 'B-$at']);
    expect(reminder.canMarkTaken, isTrue);
    expect(ReminderPayload.tryParse('no es json'), isNull);
  });

  group('projectDoses', () {
    Treatment treatment({
      String id = 't1',
      int every = 8,
      String unit = 'HOURS',
      DateTime? endDate,
      int? remaining,
      int? perDose,
    }) =>
        Treatment(
          id: id,
          medicationId: null,
          medicationName: 'Amoxicilina',
          dosage: '500 mg',
          instructions: null,
          frequencyValue: every,
          frequencyUnit: unit,
          active: true,
          remainingQuantity: remaining,
          totalQuantity: remaining,
          startDate: DateTime(2026, 9, 29, 8, 0),
          endDate: endDate,
          registrationSource: 'MANUAL',
          quantityPerDose: perDose,
        );

    test('continues the rhythm after the last real dose, up to the horizon', () {
      final fetched = [
        dose('Amoxicilina', DateTime(2026, 9, 30, 16, 0), treatmentId: 't1'),
        dose('Amoxicilina', DateTime(2026, 10, 1, 0, 0), treatmentId: 't1'),
      ];
      final projected = projectDoses([treatment()], fetched, now, horizon: const Duration(days: 1));

      expect(projected.map((d) => d.scheduledAt), [DateTime(2026, 10, 1, 8, 0)]);
      expect(projected.single.id, startsWith('projected:'));
    });

    test('stops at the end date and when the supply runs out', () {
      final fetched = [dose('Amoxicilina', DateTime(2026, 9, 30, 16, 0), treatmentId: 't1')];
      final ended = projectDoses([treatment(endDate: DateTime(2026, 10, 1))], fetched, now);
      expect(ended.last.scheduledAt, DateTime(2026, 10, 1, 16, 0));

      final supply = projectDoses([treatment(remaining: 4, perDose: 2)], fetched, now);
      expect(supply, hasLength(2));

      expect(projectDoses([treatment(remaining: 0)], const [], now), isEmpty);
    });

    test('a reminder that includes a projection has no "Tomada" action', () {
      final at = DateTime(2026, 10, 1, 8, 0);
      final projected = projectDoses([treatment()], [dose('Amoxicilina', DateTime(2026, 10, 1, 0, 0), treatmentId: 't1')], now,
          horizon: const Duration(days: 1));
      final reminders = planReminders([...projected, dose('Losartán', at)], now);

      expect(reminders.single.body, 'Amoxicilina, Losartán');
      expect(reminders.single.canMarkTaken, isFalse);
    });
  });
}
