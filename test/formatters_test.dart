import 'package:flutter_test/flutter_test.dart';

import 'package:meditrack_mobile/utils/formatters.dart';

void main() {
  group('combineDosage / splitDosage', () {
    test('round-trips an amount with a strength', () {
      final dosage = combineDosage(' 1 tableta ', ' 50mg ');
      expect(dosage, '1 tableta (50mg)');
      expect(splitDosage(dosage), ('1 tableta', '50mg'));
    });

    test('leaves out the parentheses when there is no strength', () {
      expect(combineDosage('2 gotas', ''), '2 gotas');
      expect(splitDosage('2 gotas'), ('2 gotas', ''));
    });
  });

  test('formatDayMonth writes the date in words, with the year only when it differs', () {
    final now = DateTime(2026, 10, 8);
    expect(formatDayMonth(DateTime(2026, 10, 20), now: now), '20 de octubre');
    expect(formatDayMonth(DateTime(2027, 1, 3), now: now), '3 de enero de 2027');
  });

  test('isoDate zero-pads every field', () {
    expect(isoDate(DateTime(2026, 3, 7, 9, 5)), '2026-03-07');
  });

  // These hold in any time zone — the suite runs under UTC, Madrid and Bogotá.
  group('time zones', () {
    test('isoDateTimeWithOffset keeps the wall-clock time and names its offset', () {
      final local = DateTime(2026, 9, 30, 8, 5);
      final sent = isoDateTimeWithOffset(local);

      expect(sent, startsWith('2026-09-30T08:05:00'));
      expect(sent, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
      expect(DateTime.parse(sent).isAtSameMomentAs(local), isTrue);
    });

    test('isoDateTimeWithOffset converts a UTC instant to local time first', () {
      final instant = DateTime.utc(2026, 9, 30, 13, 0);
      expect(DateTime.parse(isoDateTimeWithOffset(instant)).isAtSameMomentAs(instant), isTrue);
    });

    test('timeZoneParam is this phone\'s offset on that day', () {
      final day = DateTime(2026, 9, 30);
      final expected = DateTime(2026, 9, 30, 12).timeZoneOffset;
      final param = timeZoneParam(day);
      final sign = param.startsWith('-') ? -1 : 1;
      final parts = param.substring(1).split(':').map(int.parse).toList();

      expect(Duration(hours: parts[0], minutes: parts[1]) * sign, expected);
    });
  });

  test('daysBetween ignores the time of day', () {
    expect(daysBetween(DateTime(2026, 1, 1, 23, 59), DateTime(2026, 1, 6, 0, 1)), 5);
  });

  test('formatFrequency picks singular or plural', () {
    expect(formatFrequency(1, 'DAYS'), 'cada 1 día');
    expect(formatFrequency(8, 'HOURS'), 'cada 8 horas');
  });

  test('formatTime uses a 12-hour clock', () {
    expect(formatTime(DateTime(2026, 1, 1, 0, 5)), '12:05 a. m.');
    expect(formatTime(DateTime(2026, 1, 1, 13, 30)), '1:30 p. m.');
  });
}
