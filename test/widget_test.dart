import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/main.dart';
import 'package:meditrack_mobile/screens/login_screen.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

void main() {
  // No stored session: the app starts on the login screen.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Login screen shows the email and password fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MediTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('MediTrack'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    // Once as the card title, once as the (custom gradient) submit button's label.
    expect(find.text('Iniciar sesión'), findsNWidgets(2));
    expect(find.widgetWithText(InkWell, 'Iniciar sesión'), findsOneWidget);
  });

  testWidgets('Submitting an empty login form shows validation errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MediTrackApp());
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(InkWell, 'Iniciar sesión');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('Ingresa tu correo'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('Login screen explains when the session expired', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.build(), home: const LoginScreen(sessionExpired: true)),
    );

    expect(find.text('Tu sesión expiró. Vuelve a iniciar sesión.'), findsOneWidget);
  });

  testWidgets('Login links to account creation and password recovery', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MediTrackApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Nombre completo'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar enlace'), findsOneWidget);
  });

  testWidgets('Login screen shows a notice after a password reset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const LoginScreen(notice: 'Contraseña actualizada.'),
      ),
    );

    expect(find.text('Contraseña actualizada.'), findsOneWidget);
  });
}
