import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/api/api_client.dart';
import 'package:meditrack_mobile/models/caregiver.dart';
import 'package:meditrack_mobile/models/notification_preferences.dart';
import 'package:meditrack_mobile/models/scheduled_dose.dart';
import 'package:meditrack_mobile/screens/notification_settings_screen.dart';
import 'package:meditrack_mobile/services/dose_reminders.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

ScheduledDose pendingAt(String name, DateTime at) => ScheduledDose(
      id: '$name-$at',
      medicationName: name,
      dosage: '1 tableta',
      instructions: null,
      scheduledAt: at,
      status: DoseStatus.pending,
      recordedAt: null,
      notes: null,
      recordedByName: null,
      withinWindow: true,
      recordable: false,
    );

void main() {
  group('model', () {
    test('round-trips the backend JSON', () {
      final json = {
        'emailEnabled': false,
        'emailTiming': 'BEFORE',
        'smsEnabled': true,
        'smsTiming': 'AT_TIME',
        'phoneNumber': '+57 300 123 4567',
        'pushEnabled': true,
        'pushTiming': 'BOTH',
        'includeDependents': false,
      };
      final prefs = NotificationPreferences.fromJson(json);
      expect(prefs.emailTiming, ReminderTiming.before);
      expect(prefs.smsTiming, ReminderTiming.atTime);
      expect(prefs.toJson(), json);
    });

    test('missing fields fall back to the backend defaults', () {
      final prefs = NotificationPreferences.fromJson(const {});
      expect(prefs.emailEnabled, isTrue);
      expect(prefs.smsEnabled, isFalse);
      expect(prefs.pushEnabled, isTrue);
      expect(prefs.pushTiming, ReminderTiming.both);
      expect(prefs.includeDependents, isTrue);
    });
  });

  group('reminders follow the push preferences', () {
    final now = DateTime(2026, 10, 9, 7, 0);
    final at = DateTime(2026, 10, 9, 8, 0);
    final own = [pendingAt('Losartán', at)];
    final rosa = ProfileSummary.fromJson({'id': 'dep-1', 'name': 'Rosa', 'email': null, 'claimed': false});
    final dependents = <DependentDoses>[(profile: rosa, doses: [pendingAt('Metformina', at)])];

    test('"Ambos" schedules 10 minutes before and on time, with distinct ids', () {
      final reminders = buildReminders(
          const NotificationPreferences(pushTiming: ReminderTiming.both, includeDependents: false), own, const [], now);
      expect(reminders.map((r) => r.at), [at.subtract(const Duration(minutes: 10)), at]);
      expect(reminders.first.title, 'En 10 minutos: tu medicación');
      expect(reminders.last.title, 'Hora de tu medicación');
      expect(reminders.first.id, isNot(reminders.last.id));
    });

    test('"10 min antes" only, and "A la hora" only', () {
      final before = buildReminders(
          const NotificationPreferences(pushTiming: ReminderTiming.before, includeDependents: false), own, const [], now);
      expect(before.single.at, DateTime(2026, 10, 9, 7, 50));

      final onTime = buildReminders(
          const NotificationPreferences(pushTiming: ReminderTiming.atTime, includeDependents: false), own, const [], now);
      expect(onTime.single.at, at);
    });

    test('an early reminder that would already be in the past is skipped', () {
      final reminders = buildReminders(const NotificationPreferences(pushTiming: ReminderTiming.both),
          own, const [], DateTime(2026, 10, 9, 7, 55));
      expect(reminders.single.at, at);
    });

    test('dependents only when includeDependents, and nothing when push is off', () {
      const timing = ReminderTiming.atTime;
      final withThem = buildReminders(const NotificationPreferences(pushTiming: timing), own, dependents, now);
      expect(withThem.map((r) => r.title), ['Hora de tu medicación', 'Hora de la medicación de Rosa']);

      final without = buildReminders(
          const NotificationPreferences(pushTiming: timing, includeDependents: false), own, dependents, now);
      expect(without.map((r) => r.title), ['Hora de tu medicación']);

      expect(buildReminders(const NotificationPreferences(pushEnabled: false), own, dependents, now), isEmpty);
    });
  });

  group('settings form', () {
    Future<List<NotificationPreferences>> pump(
      WidgetTester tester, {
      NotificationPreferences initial = const NotificationPreferences(),
      bool hasDependents = false,
      String email = 'ana@example.com',
    }) async {
      final saved = <NotificationPreferences>[];
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: NotificationSettingsForm(
            initial: initial,
            email: email,
            hasDependents: hasDependents,
            onSave: (prefs) async {
              saved.add(prefs);
              return prefs;
            },
          ),
        ),
      ));
      return saved;
    }

    testWidgets('turning SMS on asks for a valid number before saving', (tester) async {
      final saved = await pump(tester);

      expect(find.text('Tu número de teléfono'), findsNothing);
      await tester.tap(find.text('Mensaje de texto (SMS)'));
      await tester.pump();
      expect(find.text('Tu número de teléfono'), findsOneWidget);

      await tester.tap(find.text('Guardar cambios'));
      await tester.pump();
      expect(find.text('Escribe el número al que enviar los SMS'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '12ab');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pump();
      expect(find.text('Ingresa un teléfono válido'), findsOneWidget);
      expect(saved, isEmpty);

      await tester.enterText(find.byType(TextFormField), '+57 300 123 4567');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(saved.single.smsEnabled, isTrue);
      expect(saved.single.phoneNumber, '+57 300 123 4567');
      expect(find.text('Cambios guardados.'), findsOneWidget);
    });

    testWidgets('the dependents switch only shows for a caregiver', (tester) async {
      await pump(tester);
      expect(find.text('Recibir avisos de las personas a mi cargo'), findsNothing);

      final saved = await pump(tester, hasDependents: true);
      await tester.tap(find.text('Recibir avisos de las personas a mi cargo'));
      await tester.pump();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(saved.single.includeDependents, isFalse);
    });

    testWidgets('timing choice is saved per channel', (tester) async {
      final saved = await pump(tester);
      // Push card comes first, email second — pick the email card's "A la hora".
      await tester.tap(find.text('A la hora').at(1));
      await tester.pump();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(saved.single.emailTiming, ReminderTiming.atTime);
      expect(saved.single.pushTiming, ReminderTiming.both);
    });

    testWidgets('a backend rejection is shown in Spanish', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: NotificationSettingsForm(
            initial: const NotificationPreferences(),
            email: '',
            hasDependents: false,
            onSave: (_) async => throw ApiException('El número de teléfono no es válido.'),
          ),
        ),
      ));
      expect(find.textContaining('Tu cuenta no tiene correo'), findsOneWidget);
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(find.text('El número de teléfono no es válido.'), findsOneWidget);
    });
  });
}
