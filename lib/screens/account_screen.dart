import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/caregiver.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/password_field.dart';
import '../widgets/section_card.dart';
import 'notification_settings_screen.dart';

// Mirrors the web's AccountSettingsModal: profile, password, and deleting the
// account — each section saves on its own.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.onNameChanged,
    required this.onAccountDeleted,
    required this.onUnauthenticated,
  });

  final ValueChanged<String> onNameChanged;
  final Future<void> Function() onAccountDeleted;
  final Future<void> Function() onUnauthenticated;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  UserProfile? _profile;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final profile = await ApiClient.getMyProfile();
      if (mounted) setState(() => _profile = profile);
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'No pudimos conectar con el servidor.');
    }
  }

  // Shared error handling for the three sections: returns the message to show,
  // or null when the session is gone and the user was sent to the login screen.
  Future<String?> _errorFor(Object error, String fallback) async {
    if (error is UnauthenticatedException) {
      await widget.onUnauthenticated();
      return null;
    }
    return error is ApiException ? error.message : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: SafeArea(
        child: profile == null
            ? Center(
                child: _loadError == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!, style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _ProfileSection(
                    profile: profile,
                    errorFor: _errorFor,
                    onSaved: (updated) {
                      setState(() => _profile = updated);
                      widget.onNameChanged(updated.name);
                    },
                  ),
                  const SizedBox(height: 12),
                  _NotificationsLink(onUnauthenticated: widget.onUnauthenticated),
                  const SizedBox(height: 12),
                  _CaregiverAccessSection(errorFor: _errorFor),
                  _PasswordSection(errorFor: _errorFor),
                  const SizedBox(height: 12),
                  _DeleteSection(errorFor: _errorFor, onDeleted: widget.onAccountDeleted),
                ],
              ),
      ),
    );
  }
}

typedef _ErrorFor = Future<String?> Function(Object error, String fallback);

class _NotificationsLink extends StatelessWidget {
  const _NotificationsLink({required this.onUnauthenticated});

  final Future<void> Function() onUnauthenticated;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      // ListTile paints on the nearest Material; SectionCard is a plain box.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: const Icon(Icons.notifications_outlined, color: AppColors.primary),
          title: const Text('Notificaciones', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          subtitle: const Text('Avisos de tomas en el teléfono, por correo o por SMS'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NotificationSettingsScreen(onUnauthenticated: onUnauthenticated),
          )),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.color = AppColors.text});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
    );
  }
}

class _Saved extends StatelessWidget {
  const _Saved(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

Widget _spinnerOr(bool loading, String label) => loading
    ? const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      )
    : Text(label);

class _ProfileSection extends StatefulWidget {
  const _ProfileSection({required this.profile, required this.errorFor, required this.onSaved});

  final UserProfile profile;
  final _ErrorFor errorFor;
  final ValueChanged<UserProfile> onSaved;

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _email = TextEditingController(text: widget.profile.email);
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      final updated = await ApiClient.updateProfile(
        name: name != widget.profile.name ? name : null,
        email: email != widget.profile.email ? email : null,
      );
      if (!mounted) return;
      widget.onSaved(updated);
      setState(() => _saved = true);
    } catch (e) {
      final message = await widget.errorFor(e, 'No pudimos guardar los cambios.');
      if (mounted && message != null) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Perfil'),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            if (_saved) const _Saved('Cambios guardados.'),
            TextFormField(
              controller: _name,
              maxLength: 150,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo', counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo electrónico'),
              validator: (v) => isValidEmail(v ?? '') ? null : 'Ingresa un correo electrónico válido',
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: _spinnerOr(_saving, 'Guardar')),
          ],
        ),
      ),
    );
  }
}

// Only shown to someone who had a caregiver manage their profile and later
// claimed it as their own account: whether that caregiver may keep seeing and
// managing their data. Hidden entirely for everyone else.
class _CaregiverAccessSection extends StatefulWidget {
  const _CaregiverAccessSection({required this.errorFor});

  final _ErrorFor errorFor;

  @override
  State<_CaregiverAccessSection> createState() => _CaregiverAccessSectionState();
}

class _CaregiverAccessSectionState extends State<_CaregiverAccessSection> {
  CaregiverAccessStatus? _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ApiClient.getCaregiverAccess().then((status) {
      if (mounted) setState(() => _status = status);
    }).catchError((_) {
      // Nothing actionable to show — the section simply stays hidden.
    });
  }

  Future<void> _toggle() async {
    final status = _status!;
    final grant = !status.granted;
    if (!grant) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Retirar el acceso?'),
          content: Text(
            '${status.caregiverName ?? 'Tu cuidador'} dejará de ver tus tratamientos, dosis y ficha SOS '
            'hasta que vuelvas a darle acceso.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retirar acceso')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.setCaregiverAccess(grant);
      if (mounted) {
        setState(() => _status = CaregiverAccessStatus(
              hasCaregiver: true,
              caregiverName: status.caregiverName,
              granted: grant,
            ));
      }
    } catch (e) {
      final message = await widget.errorFor(e, 'No pudimos actualizar el acceso.');
      if (mounted && message != null) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.hasCaregiver) return const SizedBox.shrink();
    final name = status.caregiverName ?? 'Tu cuidador';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Acceso de tu cuidador'),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            Row(
              children: [
                Icon(
                  status.granted ? Icons.verified_user_outlined : Icons.lock_outline,
                  color: status.granted ? AppColors.success : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.granted
                        ? '$name puede ver y gestionar tus datos.'
                        : '$name no tiene acceso a tus datos.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(
                  ApiClient.resolveServerUrl('/caregiver-consent'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('¿Qué significa dar acceso?'),
              ),
            ),
            status.granted
                ? OutlinedButton(
                    onPressed: _saving ? null : _toggle,
                    child: const Text('Retirar acceso'),
                  )
                : FilledButton(
                    onPressed: _saving ? null : _toggle,
                    child: _spinnerOr(_saving, 'Dar acceso'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _PasswordSection extends StatefulWidget {
  const _PasswordSection({required this.errorFor});

  final _ErrorFor errorFor;

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await ApiClient.changePassword(
        currentPassword: _current.text,
        newPassword: _new.text,
        confirmNewPassword: _confirm.text,
      );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() => _saved = true);
    } catch (e) {
      final message = await widget.errorFor(e, 'No pudimos cambiar la contraseña.');
      if (mounted && message != null) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Cambiar contraseña'),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            if (_saved)
              const _Saved('Contraseña actualizada. Se cerró la sesión en tus otros dispositivos.'),
            PasswordField(
              label: 'Contraseña actual',
              controller: _current,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña actual' : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              label: 'Nueva contraseña',
              controller: _new,
              hintText: 'Mínimo 8 caracteres',
              showStrength: true,
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.length < 8)
                  ? 'La contraseña debe tener al menos 8 caracteres'
                  : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              label: 'Confirmar nueva contraseña',
              controller: _confirm,
              validator: (v) => v != _new.text ? 'Las contraseñas no coinciden' : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _spinnerOr(_saving, 'Cambiar contraseña'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteSection extends StatefulWidget {
  const _DeleteSection({required this.errorFor, required this.onDeleted});

  final _ErrorFor errorFor;
  final Future<void> Function() onDeleted;

  @override
  State<_DeleteSection> createState() => _DeleteSectionState();
}

class _DeleteSectionState extends State<_DeleteSection> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Ya no podrás iniciar sesión con esta cuenta y se cerrará en todos tus dispositivos. '
          'Tu historial de medicación se conserva y no se borra.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.dangerStrong),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ApiClient.deleteAccount();
      await widget.onDeleted();
    } catch (e) {
      final message = await widget.errorFor(e, 'No pudimos eliminar tu cuenta.');
      if (mounted && message != null) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Eliminar cuenta', color: AppColors.dangerStrong),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          const Text(
            'Desactiva tu cuenta de forma permanente. Tu historial de medicación se conserva.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _deleting ? null : _confirmAndDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dangerStrong,
              side: const BorderSide(color: AppColors.dangerBgSoft),
            ),
            icon: _deleting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline, size: 18),
            label: const Text('Eliminar mi cuenta'),
          ),
        ],
      ),
    );
  }
}
