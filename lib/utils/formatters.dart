const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour24 = local.hour;
  final period = hour24 < 12 ? 'a. m.' : 'p. m.';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

String formatFullDate(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  final month = _months[date.month - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)}, ${date.day} de $month';
}

// "20 de octubre", adding the year only when it isn't the current one.
String formatDayMonth(DateTime date, {DateTime? now}) {
  final base = '${date.day} de ${_months[date.month - 1]}';
  return date.year == (now ?? DateTime.now()).year ? base : '$base de ${date.year}';
}

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _offset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

// A local wall-clock time with this phone's UTC offset attached, e.g.
// "2026-09-30T08:00:00-05:00" — the API's date-time contract (see the backend's
// ApiDateTimeConfig; the web sends the same shape from toOffsetDateTimeValue).
// Without the offset the backend would read it as Bogotá time.
String isoDateTimeWithOffset(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${isoDate(local)}T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '${_offset(local.timeZoneOffset)}';
}

// The `tz` query parameter for a calendar-day query: this phone's offset on
// that day (at noon, clear of any DST switch at night), so the backend's "day"
// is the user's day. An offset rather than an IANA name because Dart can't
// report the latter without a plugin — and the backend accepts both.
String timeZoneParam(DateTime day) => _offset(DateTime(day.year, day.month, day.day, 12).timeZoneOffset);

String formatDateTimeShort(DateTime date) {
  final local = date.toLocal();
  return '${local.day} de ${_months[local.month - 1]}, ${formatTime(local)}';
}

String combineDosage(String amount, String strength) {
  final trimmedAmount = amount.trim();
  final trimmedStrength = strength.trim();
  return trimmedStrength.isNotEmpty ? '$trimmedAmount ($trimmedStrength)' : trimmedAmount;
}

// Reverses combineDosage — splits a stored dosage like "1 tableta (50mg)" back
// into its two parts so it can be edited as two fields again.
(String amount, String strength) splitDosage(String dosage) {
  final match = RegExp(r'^(.*?)\s*\(([^()]+)\)\s*$').firstMatch(dosage);
  if (match != null) {
    return (match.group(1)!.trim(), match.group(2)!.trim());
  }
  return (dosage.trim(), '');
}

int daysBetween(DateTime start, DateTime end) {
  final startOfDay = DateTime(start.year, start.month, start.day);
  final endOfDay = DateTime(end.year, end.month, end.day);
  return endOfDay.difference(startOfDay).inDays;
}

String formatFrequency(int value, String unit) {
  const labels = {
    'MINUTES': ['minuto', 'minutos'],
    'HOURS': ['hora', 'horas'],
    'DAYS': ['día', 'días'],
  };
  final pair = labels[unit] ?? ['unidad', 'unidades'];
  return 'cada $value ${value == 1 ? pair[0] : pair[1]}';
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

// Same loose check as the web's register form — the backend validates for real.
bool isValidEmail(String email) => _emailPattern.hasMatch(email.trim());

// A one-time token pasted by hand: either the bare token, or a whole link that
// carries it as ?token=… — the password reset email links to the web app's
// /reset-password?token=… (which a phone may not be able to open), and an
// invite code may also be shared as a /claim-account?token=… link.
String? extractToken(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  final fromLink = uri?.queryParameters['token'];
  if (fromLink != null && fromLink.isNotEmpty) return fromLink;
  if (text.contains('://') || text.contains(' ')) return null;
  return text;
}

// Loose on purpose (the backend doesn't validate phones at all): digits plus
// the usual separators, with at least 7 digits — enough to catch typos without
// rejecting real local or international formats.
bool isValidPhone(String phone) {
  final text = phone.trim();
  if (!RegExp(r'^\+?[0-9 ()\-]+$').hasMatch(text)) return false;
  return RegExp('[0-9]').allMatches(text).length >= 7;
}
