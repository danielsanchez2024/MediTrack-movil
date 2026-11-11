import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:meditrack_mobile/api/api_client.dart';
import 'package:meditrack_mobile/models/scanned_medication.dart';
import 'package:meditrack_mobile/screens/add_treatment_screen.dart';
import 'package:meditrack_mobile/screens/scan_prescription_screen.dart';
import 'package:meditrack_mobile/theme/app_theme.dart';

// A real 1×1 PNG, so Image.memory has something valid to decode.
final _photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

// A text field currently holding exactly this value (hints don't count).
Finder fieldWithValue(String value) =>
    find.byWidgetPredicate((w) => w is EditableText && w.controller.text == value);

ScannedMedication med(String? name, {String? dosage, int? hours, int? days}) =>
    ScannedMedication(medicationName: name, dosage: dosage, frequencyHours: hours, durationDays: days);

void main() {
  group('ScannedMedication', () {
    test('blank fields count as not read, never as values', () {
      final m = ScannedMedication.fromJson({
        'medicationName': '  ',
        'dosage': '1 tableta (50mg)',
        'frequencyHours': null,
        'durationDays': 5,
      });
      expect(m.medicationName, isNull);
      expect(m.missingFields, ['nombre', 'frecuencia']);
    });
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(), home: home));
  }

  testWidgets('a scanned medication prefills the form and says what is missing', (tester) async {
    await pump(
      tester,
      AddTreatmentScreen(
        scanned: med('Losartán', dosage: '1 tableta (50mg)', days: 5),
        onUnauthenticated: () async {},
      ),
    );

    expect(fieldWithValue('Losartán'), findsOneWidget);
    expect(fieldWithValue('1 tableta'), findsOneWidget);
    expect(fieldWithValue('50mg'), findsOneWidget);
    expect(fieldWithValue('5'), findsOneWidget);
    expect(find.textContaining('No pudimos leer: frecuencia'), findsOneWidget);
    // The frequency wasn't read, so it's blank rather than the manual form's default of 8.
    // The button sits at the end of a lazily built list: scroll it into existence first.
    final submit = find.widgetWithText(FilledButton, 'Agregar medicamento');
    await tester.scrollUntilVisible(submit, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Inválido'), findsOneWidget);
  });

  testWidgets('photo → read → review each medication in the prefilled form', (tester) async {
    final scanned = <Uint8List>[];
    await pump(
      tester,
      ScanPrescriptionScreen(
        onUnauthenticated: () async {},
        chooseImage: (source) async => _photo,
        scanner: (image) async {
          scanned.add(image);
          return [med('Losartán', dosage: '1 tableta (50mg)', hours: 8, days: 5), med('Metformina', dosage: '1 tableta')];
        },
      ),
    );

    expect(find.textContaining('se envía a un servicio externo de inteligencia artificial'), findsOneWidget);
    expect(find.text('Leer fórmula'), findsNothing);

    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leer fórmula'));
    await tester.pumpAndSettle();

    expect(scanned.single, _photo);
    expect(find.text('Encontramos 2 medicamentos'), findsOneWidget);
    expect(find.text('1 tableta (50mg) · cada 8 horas · por 5 días'), findsOneWidget);
    expect(find.text('No pudimos leer: frecuencia, duración'), findsOneWidget);
    expect(find.text('Terminar (quedan 2 sin agregar)'), findsOneWidget);

    await tester.tap(find.text('Revisar y agregar').first);
    await tester.pumpAndSettle();
    expect(find.byType(AddTreatmentScreen), findsOneWidget);
    expect(fieldWithValue('Losartán'), findsOneWidget);
    expect(fieldWithValue('8'), findsOneWidget);
  });

  testWidgets('a failed read goes back to the photo with the reason', (tester) async {
    await pump(
      tester,
      ScanPrescriptionScreen(
        onUnauthenticated: () async {},
        chooseImage: (source) async => _photo,
        scanner: (image) async =>
            throw ApiException('No pudimos leer la fórmula. Intenta con otra foto o ingresa el medicamento manualmente.'),
      ),
    );

    await tester.tap(find.text('Tomar foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leer fórmula'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos leer la fórmula'), findsOneWidget);
    // The photo is kept, so trying again is one tap.
    expect(find.text('Leer fórmula'), findsOneWidget);
  });

  testWidgets('nothing found offers another photo or typing it in', (tester) async {
    await pump(
      tester,
      ScanPrescriptionScreen(
        onUnauthenticated: () async {},
        chooseImage: (source) async => _photo,
        scanner: (image) async => const [],
      ),
    );

    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leer fórmula'));
    await tester.pumpAndSettle();

    expect(find.text('No encontramos medicamentos en la foto.'), findsOneWidget);
    expect(find.text('Tomar otra foto'), findsOneWidget);
    expect(find.text('Ingresarlo a mano'), findsOneWidget);
  });

  testWidgets('camera permission denied explains what to do', (tester) async {
    await pump(
      tester,
      ScanPrescriptionScreen(
        onUnauthenticated: () async {},
        chooseImage: (source) async => throw Exception('camera_access_denied'),
        scanner: (image) async => const [],
      ),
    );

    await tester.tap(find.text('Tomar foto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No pudimos abrir la cámara'), findsOneWidget);
    expect(ImageSource.camera, isNotNull);
  });
}
