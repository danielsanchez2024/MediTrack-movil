import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/password_field.dart';
import '../widgets/section_card.dart';
import 'home_shell.dart';

// For someone whose caregiver already manages a profile for them: turns that
// profile into their own account with the invite code the caregiver shared.
// Their treatments and history carry over; from then on the caregiver only
// sees their data while they allow it (Mi cuenta → Acceso de tu cuidador).
class ClaimAccountScreen extends StatefulWidget {
  const ClaimAccountScreen({super.key});

  @override
  State<ClaimAccountScreen> createState() => _ClaimAccountScreenState();
}

class _ClaimAccountScreenState extends State<ClaimAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiClient.claimAccount(
        claimToken: extractToken(_code.text)!,
        email: _email.text.trim(),
        password: _password.text,
        confirmPassword: _confirm.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeShell(userName: result.name)),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos conectar con el servidor. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Usar código de invitación')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SectionCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Si alguien que te cuida ya lleva tu medicación en MediTrack, te habrá '
                        'dado un código. Con él creas tu propia cuenta y conservas todo tu historial.',
                        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
                      TextFormField(
                        controller: _code,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Código de invitación',
                          prefixIcon: Icon(Icons.key_outlined, color: AppColors.textMuted),
                        ),
                        validator: (v) => extractToken(v ?? '') == null ? 'Ingresa el código de invitación' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Tu correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline, color: AppColors.textMuted),
                        ),
                        validator: (v) => isValidEmail(v ?? '') ? null : 'Ingresa un correo electrónico válido',
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        label: 'Contraseña',
                        controller: _password,
                        hintText: 'Mínimo 8 caracteres',
                        showStrength: true,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.length < 8)
                            ? 'La contraseña debe tener al menos 8 caracteres'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        label: 'Confirmar contraseña',
                        controller: _confirm,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Crear mi cuenta'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
