// Same rule-based score as the web's src/lib/passwordStrength.ts — not a real
// entropy estimate, just enough to nudge people away from short,
// single-character-class passwords.
class PasswordStrength {
  const PasswordStrength(this.score, this.label);

  final int score; // 0–4
  final String label;
}

PasswordStrength scorePassword(String password) {
  if (password.isEmpty) return const PasswordStrength(0, '');

  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;

  final variety = [RegExp('[a-z]'), RegExp('[A-Z]'), RegExp('[0-9]'), RegExp('[^A-Za-z0-9]')]
      .where((pattern) => pattern.hasMatch(password))
      .length;
  if (variety >= 3) score++;
  if (variety == 4) score++;

  const labels = ['Muy débil', 'Débil', 'Aceptable', 'Fuerte', 'Muy fuerte'];
  final clamped = score.clamp(0, 4);
  return PasswordStrength(clamped, labels[clamped]);
}
