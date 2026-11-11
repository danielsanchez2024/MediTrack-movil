import 'package:flutter/material.dart';

import '../models/scheduled_dose.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

const _statusLabels = {
  DoseStatus.taken: 'Tomada',
  DoseStatus.skipped: 'Omitida',
  DoseStatus.missed: 'Perdida',
  DoseStatus.pending: 'Pendiente',
  DoseStatus.unknown: 'Pendiente',
};

// The "I made a mistake" path for an already-resolved dose — same as the web's
// DoseDetailModal. Only offered while dose.correctable: indefinitely for a
// MISSED dose (the system's own guess), 15 minutes for a person's TAKEN/SKIPPED.
// Resolves to the chosen correction; the caller stores it.
Future<(DoseStatus, String)?> showDoseCorrectionSheet(BuildContext context, ScheduledDose dose) {
  return showModalBottomSheet<(DoseStatus, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceCard,
    builder: (_) => _DoseCorrectionSheet(dose: dose),
  );
}

class _DoseCorrectionSheet extends StatefulWidget {
  const _DoseCorrectionSheet({required this.dose});

  final ScheduledDose dose;

  @override
  State<_DoseCorrectionSheet> createState() => _DoseCorrectionSheetState();
}

class _DoseCorrectionSheetState extends State<_DoseCorrectionSheet> {
  late final _notes = TextEditingController(text: widget.dose.notes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _choose(DoseStatus status) => Navigator.of(context).pop((status, _notes.text.trim()));

  @override
  Widget build(BuildContext context) {
    final dose = widget.dose;
    final missed = dose.status == DoseStatus.missed;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(dose.medicationName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(dose.dosage, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'Programada: ${formatFullDate(dose.scheduledAt)} · ${formatTime(dose.scheduledAt)}',
            style: const TextStyle(color: AppColors.textCaption, fontSize: 13),
          ),
          Text(
            'Estado: ${_statusLabels[dose.status]}'
            '${dose.recordedAt != null ? ' a las ${formatTime(dose.recordedAt!)}' : ''}'
            '${dose.recordedByName != null ? ' · registrado por ${dose.recordedByName}' : ''}',
            style: const TextStyle(color: AppColors.textCaption, fontSize: 13),
          ),
          if (dose.remainingQuantity != null)
            Text(
              'Quedan ${dose.remainingQuantity} '
              '${dose.remainingQuantity == 1 ? 'unidad' : 'unidades'} de este medicamento',
              style: const TextStyle(color: AppColors.textCaption, fontSize: 13),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: missed ? AppColors.warningBg : AppColors.surfaceInfo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              missed
                  ? 'Se marcó como perdida automáticamente porque pasó demasiado tiempo sin '
                      'registrarse. Puedes corregirla si en realidad sí se tomó.'
                  : 'Puedes corregirla hasta 15 minutos después de haberla registrado.',
              style: TextStyle(
                color: missed ? AppColors.warning : AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Observaciones (opcional)'),
          ),
          const SizedBox(height: 16),
          if (dose.status != DoseStatus.taken) ...[
            FilledButton(
              onPressed: () => _choose(DoseStatus.taken),
              child: const Text('✓ Marcar como tomada'),
            ),
            const SizedBox(height: 8),
          ],
          if (dose.status != DoseStatus.skipped) ...[
            OutlinedButton(
              onPressed: () => _choose(DoseStatus.skipped),
              child: const Text('✗ Marcar como omitida'),
            ),
            const SizedBox(height: 8),
          ],
          TextButton.icon(
            onPressed: () => _choose(DoseStatus.pending),
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Deshacer y volver a pendiente'),
          ),
        ],
      ),
    );
  }
}
