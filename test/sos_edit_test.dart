import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/emergency_card.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';
import 'package:meditrack_mobile/utils/formatters.dart';
import 'package:meditrack_mobile/widgets/allergy_sheet.dart';
import 'package:meditrack_mobile/widgets/emergency_contact_sheet.dart';

void main() {
  test('isValidPhone accepts real formats and rejects typos', () {
    expect(isValidPhone('300 123 4567'), isTrue);
    expect(isValidPhone('+57 (1) 234-5678'), isTrue);
    expect(isValidPhone('123'), isFalse);
    expect(isValidPhone('300-abc-4567'), isFalse);
  });

  // Opens a sheet from a button so it has a real route to pop.
  Future<void> openSheet(WidgetTester tester, void Function(BuildContext) open) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => open(context), child: const Text('abrir')),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('allergy sheet requires a description', (tester) async {
    await openSheet(tester, (c) => showAllergySheet(c, onUnauthenticated: () async {}));

    expect(find.text('Agregar alergia'), findsOneWidget);
    expect(find.text('Moderada'), findsOneWidget);
    expect(find.text('Eliminar alergia'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
    await tester.pump();
    expect(find.text('Requerido'), findsOneWidget);
  });

  testWidgets('editing an allergy prefills it and asks twice before deleting', (tester) async {
    await openSheet(
      tester,
      (c) => showAllergySheet(
        c,
        existing: EmergencyAllergy(id: '1', description: 'Penicilina', severity: 'SEVERE'),
        onUnauthenticated: () async {},
      ),
    );

    expect(find.text('Editar alergia'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Penicilina'), findsOneWidget);

    await tester.tap(find.text('Eliminar alergia'));
    await tester.pump();
    expect(find.text('Toca otra vez para eliminar'), findsOneWidget);
  });

  testWidgets('contact sheet validates the phone', (tester) async {
    await openSheet(tester, (c) => showEmergencyContactSheet(c, onUnauthenticated: () async {}));

    await tester.enterText(find.byType(TextFormField).first, 'María Gómez');
    await tester.enterText(find.byType(TextFormField).last, '12ab');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pump();

    expect(find.text('Ingresa un teléfono válido'), findsOneWidget);
    expect(find.text('Quitar contacto'), findsNothing);
  });
}
