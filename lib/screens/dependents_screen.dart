import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../models/caregiver.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

// The caregiver's side, mirroring the web's ManageDependentsModal: create a
// profile for someone they look after, hand them an invite code so they can
// claim it as their own account, or delete it.
class DependentsScreen extends StatefulWidget {
  const DependentsScreen({
    super.key,
    required this.dependents,
    required this.onChanged,
    required this.onUnauthenticated,
  });

  final List<ProfileSummary> dependents;
  // Reloads the list in HomeShell (and so the profile switcher) and returns it.
  final Future<List<ProfileSummary>> Function() onChanged;
  final Future<void> Function() onUnauthenticated;

  @override
  State<DependentsScreen> createState() => _DependentsScreenState();
}

class _DependentsScreenState extends State<DependentsScreen> {
  late List<ProfileSummary> _dependents = widget.dependents;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _creating = false;
  String? _createError;

  // Only kept while this screen is open: the backend never shows a code again
  // after issuing it, so this is the caregiver's one chance to pass it on.
  final _invites = <String, DependentInvite>{};
  String? _busyId;
  ({String id, String message})? _rowError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await widget.onChanged();
    if (mounted) setState(() => _dependents = list);
  }

  Future<String?> _messageFor(Object error, String fallback) async {
    if (error is UnauthenticatedException) {
      await widget.onUnauthenticated();
      return null;
    }
    return error is ApiException ? error.message : fallback;
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      final email = _email.text.trim();
      await ApiClient.createDependent(name: _name.text.trim(), email: email.isEmpty ? null : email);
      _name.clear();
      _email.clear();
      await _refresh();
    } catch (e) {
      final message = await _messageFor(e, 'No pudimos crear el perfil. Intenta de nuevo.');
      if (mounted && message != null) setState(() => _createError = message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _rowAction(String id, String fallback, Future<void> Function() action) async {
    setState(() {
      _busyId = id;
      _rowError = null;
    });
    try {
      await action();
    } catch (e) {
      final message = await _messageFor(e, fallback);
      if (mounted && message != null) setState(() => _rowError = (id: id, message: message));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _invite(ProfileSummary d) => _rowAction(d.id, 'No pudimos generar el código.', () async {
        final invite = await ApiClient.inviteDependent(d.id);
        if (mounted) setState(() => _invites[d.id] = invite);
      });

  void _cancelInvite(ProfileSummary d) => _rowAction(d.id, 'No pudimos cancelar la invitación.', () async {
        await ApiClient.cancelDependentInvite(d.id);
        if (mounted) setState(() => _invites.remove(d.id));
      });

  Future<void> _delete(ProfileSummary d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar el perfil de ${d.name}?'),
        content: Text(
          'No se borra su historial médico, pero '
          '${d.claimed ? 'perderá el acceso a su cuenta' : 'dejarás de poder gestionar sus tratamientos'} '
          'de inmediato.',
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
    await _rowAction(d.id, 'No pudimos eliminar este perfil.', () async {
      await ApiClient.deleteDependent(d.id);
      _invites.remove(d.id);
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Perfiles que cuido')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildCreateForm(),
            const SizedBox(height: 16),
            if (_dependents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Todavía no cuidas a nadie. Crea un perfil para llevar la medicación de un '
                  'familiar o paciente desde tu cuenta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final d in _dependents) ...[
                _buildDependent(d),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreateForm() {
    return SectionCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Agregar un nuevo perfil',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            if (_createError != null) ...[ErrorBanner(_createError!), const SizedBox(height: 12)],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej. Rosa Martínez',
                counterText: '',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo (opcional)',
                helperText: 'Solo si la persona algún día tendrá su propia cuenta',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty || isValidEmail(v)) ? null : 'Ingresa un correo válido',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Crear perfil'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDependent(ProfileSummary d) {
    final invite = _invites[d.id];
    final busy = _busyId == d.id;
    final error = _rowError?.id == d.id ? _rowError!.message : null;

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceInfo,
                child: Icon(Icons.person_outline, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      d.claimed ? d.email ?? 'Cuenta propia activa' : 'Sin cuenta propia — lo gestionas tú',
                      style: const TextStyle(color: AppColors.textCaption, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy ? null : () => _delete(d),
                icon: const Icon(Icons.delete_outline),
                color: AppColors.dangerStrong,
                tooltip: 'Eliminar perfil de ${d.name}',
              ),
            ],
          ),
          if (error != null) ...[const SizedBox(height: 8), ErrorBanner(error)],
          if (d.claimed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Tiene su propia cuenta: solo puedes ver sus datos mientras te dé acceso desde la suya.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            )
          else if (invite != null)
            _InviteCode(
              name: d.name,
              invite: invite,
              busy: busy,
              onCancel: () => _cancelInvite(d),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _invite(d),
                icon: busy
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.key_outlined, size: 18),
                label: const Text('Invitar a tener su propia cuenta'),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteCode extends StatelessWidget {
  const _InviteCode({required this.name, required this.invite, required this.busy, required this.onCancel});

  final String name;
  final DependentInvite invite;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final expires = '${formatFullDate(invite.expiresAt)} a las ${formatTime(invite.expiresAt)}';
    final message = 'Hola $name, este es tu código de invitación para crear tu cuenta en MediTrack: '
        '${invite.code}\nÚsalo en "¿Te invitaron? Usa tu código" en la app. Vence el $expires.';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceInfo, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Código de invitación — compártelo ahora, no se volverá a mostrar:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          SelectableText(
            invite.code,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
          ),
          Text('Vence el $expires', style: const TextStyle(color: AppColors.textCaption, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar'),
              ),
              TextButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: message)),
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Compartir'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.dangerStrong),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Cancelar invitación'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
