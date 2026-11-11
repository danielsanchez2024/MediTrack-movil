import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/emergency_card.dart';
import '../theme/app_theme.dart';
import 'error_banner.dart';

sealed class AllergySheetResult {}

class AllergySaved extends AllergySheetResult {
  AllergySaved(this.allergy);

  final EmergencyAllergy allergy;
}

class AllergyDeleted extends AllergySheetResult {}

// Adds a new allergy, or edits/deletes `existing`. Saves through the API
// itself so errors show inline, and only closes once the change is stored.
Future<AllergySheetResult?> showAllergySheet(
  BuildContext context, {
  EmergencyAllergy? existing,
  String? profileId,
  required Future<void> Function() onUnauthenticated,
}) {
  return showModalBottomSheet<AllergySheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceCard,
    builder: (_) => _AllergySheet(
      existing: existing,
      profileId: profileId,
      onUnauthenticated: onUnauthenticated,
    ),
  );
}

class _AllergySheet extends StatefulWidget {
  const _AllergySheet({required this.existing, required this.profileId, required this.onUnauthenticated});

  final EmergencyAllergy? existing;
  final String? profileId;
  final Future<void> Function() onUnauthenticated;

  @override
  State<_AllergySheet> createState() => _AllergySheetState();
}

class _AllergySheetState extends State<_AllergySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late String _severity = widget.existing?.severity ?? 'MODERATE';
  bool _saving = false;
  bool _confirmingDelete = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AllergySheetResult> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted) Navigator.of(context).pop(result);
    } on UnauthenticatedException {
      if (mounted) Navigator.of(context).pop();
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar los cambios. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();
    final existing = widget.existing;
    _run(() async => AllergySaved(existing == null
        ? await ApiClient.addAllergy(description, _severity, profileId: widget.profileId)
        : await ApiClient.updateAllergy(existing.id, description, _severity, profileId: widget.profileId)));
  }

  void _delete() {
    if (!_confirmingDelete) {
      setState(() => _confirmingDelete = true);
      return;
    }
    _run(() async {
      await ApiClient.deleteAllergy(widget.existing!.id, profileId: widget.profileId);
      return AllergyDeleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Editar alergia' : 'Agregar alergia',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              ErrorBanner(_error!),
              const SizedBox(height: 12),
            ],
            const Text('¿A qué es alérgico?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionController,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Ej. Penicilina'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            const Text('Gravedad', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                for (final entry in allergySeverityLabels.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_severity},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _severity = value.single),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving && !_confirmingDelete
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(editing ? 'Guardar' : 'Agregar'),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.dangerStrong),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(_confirmingDelete ? 'Toca otra vez para eliminar' : 'Eliminar alergia'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
