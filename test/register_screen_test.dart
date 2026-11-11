import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/screens/register_screen.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

void main() {
  Future<void> pumpRegister(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: const RegisterScreen()));
  }

  Finder field(String hint) => find.widgetWithText(TextFormField, hint);

  Future<void> submit(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('an empty form shows every field error', (tester) async {
    await pumpRegister(tester);
    await submit(tester);

    expect(find.text('Ingresa tu nombre completo'), findsOneWidget);
    expect(find.text('Ingresa un correo electrónico válido'), findsOneWidget);
    expect(find.text('La contraseña debe tener al menos 8 caracteres'), findsOneWidget);
  });

  testWidgets('mismatched passwords and missing consent are caught before calling the API',
      (tester) async {
    await pumpRegister(tester);
    await tester.enterText(field('Tu nombre y apellido'), 'Ana Pérez');
    await tester.enterText(field('tu@correo.com'), 'ana@correo.com');
    await tester.enterText(field('Mínimo 8 caracteres'), 'Abcdefgh123!');
    await tester.enterText(find.byType(TextFormField).last, 'otra-cosa');
    await submit(tester);

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(find.text('Muy fuerte'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, 'Abcdefgh123!');
    await submit(tester);

    expect(find.text('Las contraseñas no coinciden'), findsNothing);
    expect(
      find.text('Debes aceptar el tratamiento de datos de salud para registrarte.'),
      findsOneWidget,
    );
  });
}
