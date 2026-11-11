import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/password_field.dart';
import '../widgets/section_card.dart';
import 'home_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _consentAccepted = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consentAccepted) {
      setState(() => _error = 'Debes aceptar el tratamiento de datos de salud para registrarte.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiClient.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        confirmPassword: _confirmController.text,
        healthDataConsentAccepted: _consentAccepted,
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

  Future<void> _openPolicy() async {
    final opened = await launchUrl(
      ApiClient.resolveServerUrl('/privacy-policy'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la política.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SectionCard(
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          ErrorBanner(_error!),
                          const SizedBox(height: 16),
                        ],
                        const _Label('Nombre completo'),
                        TextFormField(
                          controller: _nameController,
                          maxLength: 150,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            hintText: 'Tu nombre y apellido',
                            counterText: '',
                            prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre completo' : null,
                        ),
                        const SizedBox(height: 16),
                        const _Label('Correo electrónico'),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(Icons.mail_outline, color: AppColors.textMuted),
                          ),
                          validator: (v) =>
                              isValidEmail(v ?? '') ? null : 'Ingresa un correo electrónico válido',
                        ),
                        const SizedBox(height: 16),
                        PasswordField(
                          label: 'Contraseña',
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
                          validator: (v) =>
                              v != _passwordController.text ? 'Las contraseñas no coinciden' : null,
                        ),
                        const SizedBox(height: 16),
                        Material(
                          color: AppColors.surfaceMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CheckboxListTile(
                            value: _consentAccepted,
                            onChanged: (v) => setState(() => _consentAccepted = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Acepto que MediTrack trate mis datos de salud para brindarme el '
                              'servicio de seguimiento de medicación, según la política de '
                              'tratamiento de datos.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _openPolicy,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Leer la política de tratamiento de datos'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Crear cuenta'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading ? null : () => Navigator.of(context).pop(),
                          child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                        ),
                      ],
                    ),
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
