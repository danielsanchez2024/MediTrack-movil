import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';
import 'reset_password_screen.dart';

// Submitting always ends on the same "check your inbox" message, whether or
// not the email has an account — the backend deliberately doesn't say either,
// so as not to reveal which emails are registered.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.initialEmail);

  bool _loading = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient.requestPasswordReset(_emailController.text.trim());
      if (mounted) setState(() => _submitted = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos conectar con el servidor. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openReset() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SectionCard(child: _submitted ? _buildSubmitted() : _buildForm()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu '
            'contraseña.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            ErrorBanner(_error!),
            const SizedBox(height: 16),
          ],
          const Text('Correo electrónico',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'tu@correo.com',
              prefixIcon: Icon(Icons.mail_outline, color: AppColors.textMuted),
            ),
            validator: (v) => isValidEmail(v ?? '') ? null : 'Ingresa un correo electrónico válido',
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
                : const Text('Enviar enlace'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _openReset, child: const Text('Ya tengo el enlace del correo')),
        ],
      ),
    );
  }

  Widget _buildSubmitted() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 44, color: AppColors.secondary),
        const SizedBox(height: 12),
        const Text(
          'Revisa tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Si ${_emailController.text.trim()} tiene una cuenta en MediTrack, le enviamos un '
          'enlace para restablecer tu contraseña. Revisa tu bandeja de entrada y la carpeta '
          'de spam.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _openReset, child: const Text('Ya tengo el enlace del correo')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver a iniciar sesión'),
        ),
      ],
    );
  }
}
