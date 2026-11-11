import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/caregiver.dart';
import 'package:meditrack_mobile/models/scheduled_dose.dart';
import 'package:meditrack_mobile/screens/claim_account_screen.dart';
import 'package:meditrack_mobile/screens/dependents_screen.dart';
import 'package:meditrack_mobile/services/dose_reminders.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

ScheduledDose pendingAt(DateTime at) => ScheduledDose(
      id: 'd-$at',
      medicationName: 'Losartán',
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
  group('models', () {
    test('a dependent profile', () {
      final p = ProfileSummary.fromJson({'id': '1', 'name': 'Rosa', 'email': null, 'claimed': false});
      expect(p.claimed, isFalse);
      expect(p.email, isNull);
    });

    test('an invite converts its expiry to local time', () {
      final invite = DependentInvite.fromJson({
        'claimToken': 'abc-123',
        'expiresAt': '2026-10-07T08:00:00-05:00',
      });
      expect(invite.code, 'abc-123');
      expect(invite.expiresAt.isAtSameMomentAs(DateTime.utc(2026, 10, 7, 13)), isTrue);
      expect(invite.expiresAt.isUtc, isFalse);
    });
  });

  group('reminders for dependents', () {
    final now = DateTime(2026, 9, 30, 7, 0);
    final at = DateTime(2026, 9, 30, 8, 0);

    test('name the person and never collide with the user\'s own reminder', () {
      final own = planReminders([pendingAt(at)], now).single;
      final rosa = planReminders([pendingAt(at)], now, forName: 'Rosa', slot: 1).single;
      final luis = planReminders([pendingAt(at)], now, forName: 'Luis', slot: 2).single;

      expect(own.title, 'Hora de tu medicación');
      expect(rosa.title, 'Hora de la medicación de Rosa');
      expect({own.id, rosa.id, luis.id}, hasLength(3));
      expect([own.id, rosa.id, luis.id].every((id) => id >= 0), isTrue);
    });

    test('ids stay stable for the same minute and profile', () {
      final a = planReminders([pendingAt(at)], now, forName: 'Rosa', slot: 1).single.id;
      final b = planReminders([pendingAt(at.add(const Duration(seconds: 40)))], now, forName: 'Rosa', slot: 1)
          .single
          .id;
      expect(a, b);
    });
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: screen));
  }

  testWidgets('dependents list tells managed and claimed profiles apart', (tester) async {
    await pump(
      tester,
      DependentsScreen(
        dependents: [
          ProfileSummary(id: '1', name: 'Rosa', email: null, claimed: false),
          ProfileSummary(id: '2', name: 'Luis', email: 'luis@correo.com', claimed: true),
        ],
        onChanged: () async => const [],
        onUnauthenticated: () async {},
      ),
    );

    expect(find.text('Sin cuenta propia — lo gestionas tú'), findsOneWidget);
    expect(find.text('luis@correo.com'), findsOneWidget);
    // Only the unclaimed profile can still be invited.
    expect(find.text('Invitar a tener su propia cuenta'), findsOneWidget);
    expect(find.textContaining('solo puedes ver sus datos mientras te dé acceso'), findsOneWidget);
  });

  testWidgets('creating a dependent needs a name, the email is optional but must be valid',
      (tester) async {
    await pump(
      tester,
      DependentsScreen(dependents: const [], onChanged: () async => const [], onUnauthenticated: () async {}),
    );

    expect(find.textContaining('Todavía no cuidas a nadie'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo (opcional)'), 'rosa@');
    await tester.tap(find.text('Crear perfil'));
    await tester.pump();

    expect(find.text('Requerido'), findsOneWidget);
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
  });

  testWidgets('claiming an account validates every field', (tester) async {
    await pump(tester, const ClaimAccountScreen());

    final submit = find.widgetWithText(FilledButton, 'Crear mi cuenta');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('Ingresa el código de invitación'), findsOneWidget);
    expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
    expect(find.text('La contraseña debe tener al menos 8 caracteres'), findsOneWidget);
  });
}
