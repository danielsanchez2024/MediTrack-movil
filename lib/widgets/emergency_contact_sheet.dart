import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'error_banner.dart';

// Edits the one emergency contact shown on the SOS card. Resolves to true once
// the change is stored on the backend.
Future<bool?> showEmergencyContactSheet(
  BuildContext context, {
  String? currentName,
  String? currentPhone,
  String? profileId,
  required Future<void> Function() onUnauthenticated,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceCard,
    builder: (_) => _EmergencyContactSheet(
      currentName: currentName,
      currentPhone: currentPhone,
      profileId: profileId,
      onUnauthenticated: onUnauthenticated,
    ),
  );
}

class _EmergencyContactSheet extends StatefulWidget {
  const _EmergencyContactSheet({
    required this.currentName,
    required this.currentPhone,
    required this.profileId,
    required this.onUnauthenticated,
  });

  final String? currentName;
  final String? currentPhone;
  final String? profileId;
  final Future<void> Function() onUnauthenticated;

  @override
  State<_EmergencyContactSheet> createState() => _EmergencyContactSheetState();
}

class _EmergencyContactSheetState extends State<_EmergencyContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.currentName);
  late final _phoneController = TextEditingController(text: widget.currentPhone);
  bool _saving = false;
  bool _confirmingRemove = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _store({String? name, String? phone}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.updateEmergencyContact(name: name, phone: phone, profileId: widget.profileId);
      if (mounted) Navigator.of(context).pop(true);
    } on UnauthenticatedException {
      if (mounted) Navigator.of(context).pop();
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar el contacto. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _store(name: _nameController.text.trim(), phone: _phoneController.text.trim());
  }

  void _remove() {
    if (!_confirmingRemove) {
      setState(() => _confirmingRemove = true);
      return;
    }
    _store(name: null, phone: null);
  }

  @override
  Widget build(BuildContext context) {
    final hasContact = widget.currentName != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Contacto de emergencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Aparece en tu ficha SOS para que quien te atienda pueda llamarle.',
              style: TextStyle(color: AppColors.textCaption, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              ErrorBanner(_error!),
              const SizedBox(height: 12),
            ],
            const Text('Nombre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Ej. María Gómez (hija)',
                prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            const Text('Teléfono', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                hintText: 'Ej. 300 123 4567',
                prefixIcon: Icon(Icons.phone_outlined, color: AppColors.textMuted),
              ),
              validator: (v) => isValidPhone(v ?? '') ? null : 'Ingresa un teléfono válido',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving && !_confirmingRemove
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Guardar'),
            ),
            if (hasContact) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: AppColors.dangerStrong),
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: Text(_confirmingRemove ? 'Toca otra vez para quitarlo' : 'Quitar contacto'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
