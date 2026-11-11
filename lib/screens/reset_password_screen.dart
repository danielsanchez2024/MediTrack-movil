import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/password_field.dart';
import '../widgets/section_card.dart';
import 'login_screen.dart';

// The reset email's link opens the web app, which a phone can't always reach
// (and the app has no deep links yet) — so the link can be pasted in here
// instead to choose the new password without leaving the app.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _linkController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _linkController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient.resetPassword(
        resetToken: extractToken(_linkController.text)!,
        newPassword: _passwordController.text,
        confirmPassword: _confirmController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            notice: 'Contraseña actualizada. Inicia sesión con tu nueva contraseña.',
          ),
        ),
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
      appBar: AppBar(title: const Text('Nueva contraseña')),
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
                        'Copia el enlace del botón "Restablecer contraseña" del correo que te '
                        'enviamos y pégalo aquí.',
                        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null) ...[
                        ErrorBanner(_error!),
                        const SizedBox(height: 16),
                      ],
                      const Text('Enlace del correo',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _linkController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'https://…/reset-password?token=…',
                          prefixIcon: Icon(Icons.link, color: AppColors.textMuted),
                        ),
                        validator: (v) => extractToken(v ?? '') == null
                            ? 'Pega el enlace completo del correo'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        label: 'Nueva contraseña',
                        controller: _passwordController,
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
                        controller: _confirmController,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) =>
                            v != _passwordController.text ? 'Las contraseñas no coinciden' : null,
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
                            : const Text('Guardar contraseña'),
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
