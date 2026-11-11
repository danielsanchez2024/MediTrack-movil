import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/treatment.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/section_card.dart';
import '../widgets/add_treatment_choice.dart';

enum _View { active, history }

class TreatmentsScreen extends StatefulWidget {
  const TreatmentsScreen({
    super.key,
    this.profileId,
    this.profileName,
    required this.onUnauthenticated,
    required this.dataVersion,
    required this.onDataChanged,
  });

  // Set when a caregiver is looking at a dependent's treatments.
  final String? profileId;
  final String? profileName;
  final Future<void> Function() onUnauthenticated;
  final int dataVersion;
  final VoidCallback onDataChanged;

  @override
  State<TreatmentsScreen> createState() => _TreatmentsScreenState();
}

class _TreatmentsScreenState extends State<TreatmentsScreen> {
  _View _view = _View.active;
  List<Treatment>? _treatments;
  List<Treatment>? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TreatmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataVersion != widget.dataVersion) {
      _load();
      if (_view == _View.history) {
        _loadHistory(force: true);
      } else {
        _history = null;
      }
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final treatments = await ApiClient.getTreatments(profileId: widget.profileId);
      if (!mounted) return;
      setState(() => _treatments = treatments);
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No pudimos conectar con el servidor.');
    }
  }

  Future<void> _loadHistory({bool force = false}) async {
    if (_history != null && !force) return;
    try {
      final history = await ApiClient.getInactiveTreatments(profileId: widget.profileId);
      if (!mounted) return;
      setState(() => _history = history);
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No pudimos cargar el historial.');
    }
  }

  void _onDeactivated(String id) {
    setState(() {
      _treatments = _treatments?.where((t) => t.id != id).toList();
      _history = null;
    });
    widget.onDataChanged();
  }

  void _onUpdated(Treatment updated) {
    setState(() {
      _treatments = _treatments?.map((t) => t.id == updated.id ? updated : t).toList();
    });
    widget.onDataChanged();
  }

  Future<void> _openAddTreatment() async {
    final created = await openAddTreatment(
      context,
      profileId: widget.profileId,
      profileName: widget.profileName,
      onUnauthenticated: widget.onUnauthenticated,
    );
    if (created) widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTreatment,
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: RefreshIndicator(
        onRefresh: _view == _View.active ? _load : () => _loadHistory(force: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_treatments == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _treatments == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Reintentar'))),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          widget.profileName != null ? 'Tratamientos de ${widget.profileName}' : 'Mis tratamientos',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _TabButton(
                label: 'Activos',
                selected: _view == _View.active,
                onTap: () => setState(() => _view = _View.active),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TabButton(
                label: 'Historial',
                selected: _view == _View.history,
                onTap: () {
                  setState(() => _view = _View.history);
                  _loadHistory();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_view == _View.active) ..._buildActiveList() else ..._buildHistoryList(),
      ],
    );
  }

  List<Widget> _buildActiveList() {
    final treatments = _treatments ?? [];
    if (treatments.isEmpty) {
      return [_emptyState('Todavía no tienes tratamientos activos', Icons.medication_outlined)];
    }
    return [
      for (final treatment in treatments) ...[
        _TreatmentTile(
          // Keyed by id: without it, removing a tile hands its state (confirm
          // box, spinner, edit fields) to whichever treatment slides into its slot.
          key: ValueKey(treatment.id),
          treatment: treatment,
          onDeactivated: () => _onDeactivated(treatment.id),
          onUpdated: _onUpdated,
          onUnauthenticated: widget.onUnauthenticated,
          profileId: widget.profileId,
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildHistoryList() {
    if (_history == null) {
      return [const Center(child: CircularProgressIndicator())];
    }
    if (_history!.isEmpty) {
      return [_emptyState('No hay tratamientos desactivados', Icons.history)];
    }
    return [
      for (final treatment in _history!) ...[
        _HistoryTile(key: ValueKey(treatment.id), treatment: treatment),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _emptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({super.key, required this.treatment});

  final Treatment treatment;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.8,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    treatment.medicationName,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Desactivado',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textCaption)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${treatment.dosage}'
              '${treatment.frequencyValue != null && treatment.frequencyUnit != null ? ' · ${formatFrequency(treatment.frequencyValue!, treatment.frequencyUnit!)}' : ''}'
              '${treatment.endDate != null ? ' · hasta el ${formatDayMonth(treatment.endDate!)}' : ''}',
              style: const TextStyle(color: AppColors.textCaption, fontSize: 12.5),
            ),
            if (treatment.instructions?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  treatment.instructions!,
                  style: const TextStyle(
                      color: AppColors.textCaption, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TreatmentTile extends StatefulWidget {
  const _TreatmentTile({
    super.key,
    required this.treatment,
    required this.onDeactivated,
    required this.onUpdated,
    required this.onUnauthenticated,
    required this.profileId,
  });

  final Treatment treatment;
  final VoidCallback onDeactivated;
  final void Function(Treatment updated) onUpdated;
  final Future<void> Function() onUnauthenticated;
  final String? profileId;

  @override
  State<_TreatmentTile> createState() => _TreatmentTileState();
}

enum _DurationType { defined, continuous }

class _TreatmentTileState extends State<_TreatmentTile> {
  bool _editing = false;
  bool _confirmingDeactivate = false;
  bool _saving = false;
  bool _deactivating = false;
  String? _error;

  final _dosageAmount = TextEditingController();
  final _dosageStrength = TextEditingController();
  final _frequencyValue = TextEditingController();
  final _durationDays = TextEditingController();
  final _instructions = TextEditingController();
  String _frequencyUnit = 'HOURS';
  _DurationType _durationType = _DurationType.continuous;

  @override
  void initState() {
    super.initState();
    _resetFieldsFromTreatment();
  }

  void _resetFieldsFromTreatment() {
    final t = widget.treatment;
    final (amount, strength) = splitDosage(t.dosage);
    _dosageAmount.text = amount;
    _dosageStrength.text = strength;
    _frequencyValue.text = '${t.frequencyValue ?? ''}';
    _frequencyUnit = t.frequencyUnit ?? 'HOURS';
    _durationType = t.endDate != null ? _DurationType.defined : _DurationType.continuous;
    _durationDays.text = t.endDate != null && t.startDate != null
        ? '${daysBetween(t.startDate!, t.endDate!)}'
        : '';
    _instructions.text = t.instructions ?? '';
  }

  @override
  void dispose() {
    _dosageAmount.dispose();
    _dosageStrength.dispose();
    _frequencyValue.dispose();
    _durationDays.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _confirmingDeactivate = false;
      _error = null;
      _resetFieldsFromTreatment();
      _editing = true;
    });
  }

  // Null when the edit form is valid, otherwise the message to show.
  String? _validateEdit() {
    if (_dosageAmount.text.trim().isEmpty) return 'Indica la cantidad a tomar.';
    final frequency = int.tryParse(_frequencyValue.text.trim());
    if (frequency == null || frequency <= 0) {
      return 'La frecuencia debe ser un número entero mayor que 0.';
    }
    if (_durationType == _DurationType.defined) {
      final days = int.tryParse(_durationDays.text.trim());
      if (days == null || days <= 0) {
        return 'La duración debe ser un número entero de días mayor que 0.';
      }
    }
    return null;
  }

  Future<void> _saveEdit() async {
    final validationError = _validateEdit();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final t = widget.treatment;
    final payload = <String, dynamic>{
      'dosage': combineDosage(_dosageAmount.text, _dosageStrength.text),
      'frequencyValue': int.parse(_frequencyValue.text.trim()),
      'frequencyUnit': _frequencyUnit,
      // A blank string clears them on the backend (null would mean "leave as is").
      'instructions': _instructions.text.trim(),
      if (_durationType == _DurationType.defined)
        'endDate': isoDate(
          (t.startDate ?? DateTime.now()).add(Duration(days: int.parse(_durationDays.text.trim()))),
        )
      else
        'clearEndDate': true,
    };

    try {
      final updated = await ApiClient.updateTreatment(t.id, payload, profileId: widget.profileId);
      if (!mounted) return;
      widget.onUpdated(updated);
      setState(() => _editing = false);
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar los cambios.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    setState(() => _deactivating = true);
    try {
      await ApiClient.deactivateTreatment(widget.treatment.id, profileId: widget.profileId);
      widget.onDeactivated();
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _deactivating = false;
        _confirmingDeactivate = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos desactivar el tratamiento.';
        _deactivating = false;
        _confirmingDeactivate = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final treatment = widget.treatment;

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(treatment.medicationName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      '${treatment.dosage}'
                      '${treatment.frequencyValue != null && treatment.frequencyUnit != null ? ' · ${formatFrequency(treatment.frequencyValue!, treatment.frequencyUnit!)}' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    if (treatment.endDate != null)
                      Text('hasta el ${formatDayMonth(treatment.endDate!)}',
                          style: const TextStyle(color: AppColors.textCaption, fontSize: 12)),
                    if (treatment.instructions?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          treatment.instructions!,
                          style: const TextStyle(
                              color: AppColors.textCaption, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (treatment.remainingQuantity != null && treatment.totalQuantity != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _SupplyBar(
                          remaining: treatment.remainingQuantity!,
                          total: treatment.totalQuantity!,
                        ),
                      ),
                  ],
                ),
              ),
              if (!_editing) ...[
                IconButton(
                  onPressed: _startEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppColors.textSecondary,
                  tooltip: 'Editar',
                ),
                IconButton(
                  onPressed: () => setState(() => _confirmingDeactivate = true),
                  icon: const Icon(Icons.block, size: 20),
                  color: AppColors.dangerStrong,
                  tooltip: 'Desactivar',
                ),
              ],
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.dangerStrong, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
            ),
          if (_confirmingDeactivate) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No se borra del historial, pero deja de generar tomas nuevas. ¿Desactivar?',
                    style: TextStyle(color: AppColors.warning, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _confirmingDeactivate = false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.dangerStrong, minimumSize: const Size(0, 36)),
                        onPressed: _deactivating ? null : _deactivate,
                        child: _deactivating
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sí, desactivar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (_editing) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dosageAmount,
                    decoration: const InputDecoration(labelText: 'Cantidad a tomar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _dosageStrength,
                    decoration: const InputDecoration(labelText: 'Gramaje'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _frequencyValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Frecuencia'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _frequencyUnit,
                    items: const [
                      DropdownMenuItem(value: 'MINUTES', child: Text('minutos')),
                      DropdownMenuItem(value: 'HOURS', child: Text('horas')),
                      DropdownMenuItem(value: 'DAYS', child: Text('días')),
                    ],
                    onChanged: (value) => setState(() => _frequencyUnit = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Cambiar esto reemplaza las tomas pendientes por el nuevo horario.',
              style: TextStyle(color: AppColors.textCaption, fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniChoiceButton(
                    label: 'Duración definida',
                    selected: _durationType == _DurationType.defined,
                    onTap: () => setState(() => _durationType = _DurationType.defined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniChoiceButton(
                    label: 'Continuo',
                    selected: _durationType == _DurationType.continuous,
                    onTap: () => setState(() => _durationType = _DurationType.continuous),
                  ),
                ),
              ],
            ),
            if (_durationType == _DurationType.defined) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _durationDays,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('días desde la primera dosis',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _instructions,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Instrucciones'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _saveEdit,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniChoiceButton extends StatelessWidget {
  const _MiniChoiceButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SupplyBar extends StatelessWidget {
  const _SupplyBar({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    final low = ratio <= 0.2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.surfaceMuted,
            color: low ? AppColors.warning : AppColors.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$remaining de $total unidades restantes',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: low ? AppColors.warning : AppColors.textCaption,
          ),
        ),
      ],
    );
  }
}
