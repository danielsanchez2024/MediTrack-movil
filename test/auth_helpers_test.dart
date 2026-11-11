import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/utils/error_messages.dart';
import 'package:meditrack_mobile/utils/formatters.dart';
import 'package:meditrack_mobile/utils/password_strength.dart';

void main() {
  group('toSpanishMessage', () {
    test('translates known backend messages, exactly and by prefix', () {
      expect(toSpanishMessage('Invalid email or password'), 'Email o contraseña incorrectos.');
      expect(
        toSpanishMessage('You must record doses in order: 2026-09-30T08:00'),
        startsWith('Hay una dosis anterior'),
      );
    });

    test('never leaks unknown English text', () {
      expect(toSpanishMessage('Some new backend error'),
          'Ocurrió un error. Intenta de nuevo en un momento.');
    });

    test('joins validation details and drops repeats', () {
      expect(
        toSpanishMessages(['Name is required', 'Name is required', 'Email is required']),
        'El nombre es obligatorio. El correo electrónico es obligatorio.',
      );
    });
  });

  test('scorePassword matches the web rules', () {
    expect(scorePassword('').label, '');
    expect(scorePassword('abc').score, 0);
    expect(scorePassword('abcdefgh').label, 'Débil');
    expect(scorePassword('Abcdefg1').label, 'Aceptable');
    expect(scorePassword('Abcdefgh123!').label, 'Muy fuerte');
  });

  test('isValidEmail', () {
    expect(isValidEmail(' ana@correo.com '), isTrue);
    expect(isValidEmail('ana@correo'), isFalse);
    expect(isValidEmail('ana correo.com'), isFalse);
  });

  group('extractToken', () {
    test('takes the token out of the emailed link', () {
      expect(extractToken('http://localhost/reset-password?token=abc-123'), 'abc-123');
    });

    test('accepts a bare token', () {
      expect(extractToken('  abc-123 '), 'abc-123');
    });

    test('rejects links without a token and empty input', () {
      expect(extractToken('http://localhost/reset-password'), isNull);
      expect(extractToken('   '), isNull);
    });
  });
}
