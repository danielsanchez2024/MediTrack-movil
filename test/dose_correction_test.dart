import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/scheduled_dose.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';
import 'package:meditrack_mobile/widgets/dose_card.dart';

ScheduledDose dose(DoseStatus status, {bool correctable = true, bool recordable = true}) => ScheduledDose(
      id: 'd1',
      medicationName: 'Losartán',
      dosage: '1 tableta (50mg)',
      instructions: null,
      scheduledAt: DateTime(2026, 9, 30, 8, 0),
      status: status,
      recordedAt: status == DoseStatus.missed || status == DoseStatus.pending ? null : DateTime(2026, 9, 30, 8, 5),
      notes: null,
      recordedByName: null,
      withinWindow: true,
      recordable: recordable,
      correctable: correctable,
      remainingQuantity: 12,
    );

void main() {
  Future<List<(DoseStatus, String)>> pumpCard(WidgetTester tester, ScheduledDose d,
      {DateTime? now, List<(DoseStatus, String)>? into}) async {
    final recorded = into ?? <(DoseStatus, String)>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: DoseCard(
          dose: d,
          now: now ?? DateTime(2026, 9, 30, 8, 10),
          saving: false,
          onRecord: (status, notes) => recorded.add((status, notes)),
        ),
      ),
    ));
    return recorded;
  }

  testWidgets('no Corregir once the correction window has passed', (tester) async {
    await pumpCard(tester, dose(DoseStatus.taken, correctable: false));
    expect(find.text('Corregir'), findsNothing);
  });

  testWidgets('a taken dose can be switched to skipped, with notes', (tester) async {
    final recorded = await pumpCard(tester, dose(DoseStatus.taken));

    await tester.tap(find.text('Corregir'));
    await tester.pumpAndSettle();

    expect(find.text('Quedan 12 unidades de este medicamento'), findsOneWidget);
    expect(find.text('✓ Marcar como tomada'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Me equivoqué de botón');
    await tester.tap(find.text('✗ Marcar como omitida'));
    await tester.pumpAndSettle();

    expect(recorded, [(DoseStatus.skipped, 'Me equivoqué de botón')]);
  });

  testWidgets('a missed dose explains itself and can be marked as taken', (tester) async {
    final recorded = await pumpCard(tester, dose(DoseStatus.missed));

    await tester.tap(find.text('Corregir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Se marcó como perdida automáticamente'), findsOneWidget);
    await tester.tap(find.text('✓ Marcar como tomada'));
    await tester.pumpAndSettle();

    expect(recorded.single.$1, DoseStatus.taken);
  });

  testWidgets('an upcoming dose unlocks 10 minutes before, without refetching', (tester) async {
    // Fetched while still locked: the server said recordable=false.
    final d = dose(DoseStatus.pending, recordable: false);
    await pumpCard(tester, d, now: DateTime(2026, 9, 30, 7, 49, 30));
    expect(find.text('Disponible en 1 minuto'), findsOneWidget);

    await pumpCard(tester, d, now: DateTime(2026, 9, 30, 7, 50));
    expect(find.text('✓ Marcar como tomada'), findsOneWidget);
  });

  testWidgets('"Omitida" asks before recording', (tester) async {
    final recorded = await pumpCard(tester, dose(DoseStatus.pending));

    await tester.tap(find.text('✗ Omitida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(recorded, isEmpty);

    await tester.tap(find.text('✗ Omitida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, omitida'));
    await tester.pumpAndSettle();
    expect(recorded.single.$1, DoseStatus.skipped);
  });
}
