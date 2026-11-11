import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/models/consent_status.dart';
import 'package:meditrack_mobile/screens/consent_gate_screen.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

void main() {
  Future<void> pumpGate(WidgetTester tester, {VoidCallback? onLogout}) {
    return tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: ConsentGateScreen(
        status: ConsentStatus(
          requiresAcceptance: true,
          version: 'v1.1',
          contentUrl: 'http://localhost/privacy-policy',
        ),
        onAccepted: () {},
        onLogout: onLogout ?? () {},
        onUnauthenticated: () async {},
      ),
    ));
  }

  FilledButton acceptButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Aceptar y continuar'));

  testWidgets('Accept stays disabled until the checkbox is ticked', (tester) async {
    await pumpGate(tester);

    expect(find.textContaining('versión v1.1'), findsOneWidget);
    expect(find.text('Leer la política completa'), findsOneWidget);
    expect(acceptButton(tester).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(acceptButton(tester).onPressed, isNotNull);
  });

  testWidgets('Salir logs out without accepting', (tester) async {
    var loggedOut = false;
    await pumpGate(tester, onLogout: () => loggedOut = true);

    await tester.tap(find.text('Salir'));
    expect(loggedOut, isTrue);
  });
}
