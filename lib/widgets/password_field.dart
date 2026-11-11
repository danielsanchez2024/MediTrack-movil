import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/password_strength.dart';

// Password input with a show/hide toggle and, optionally, the same strength
// meter the web's PasswordField shows while choosing a new password.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText = '••••••••',
    this.showStrength = false,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool showStrength;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  static const _strengthColors = [
    AppColors.dangerStrong,
    AppColors.dangerStrong,
    AppColors.warning,
    AppColors.secondary,
    AppColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          onChanged: widget.showStrength ? (_) => setState(() {}) : null,
          validator: widget.validator,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        if (widget.showStrength && widget.controller.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          _StrengthMeter(strength: scorePassword(widget.controller.text)),
        ],
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final color = _PasswordFieldState._strengthColors[strength.score];
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < strength.score ? color : AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: 4),
        Text(
          strength.label,
          style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
