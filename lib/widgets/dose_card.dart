import 'package:flutter/material.dart';

import '../models/scheduled_dose.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart' as fmt;
import 'dose_correction_sheet.dart';

String _formatTime(DateTime dt) => fmt.formatTime(dt);

class DoseCard extends StatefulWidget {
  const DoseCard({
    super.key,
    required this.dose,
    required this.now,
    required this.saving,
    required this.onRecord,
  });

  final ScheduledDose dose;
  final DateTime now;
  final bool saving;
  final void Function(DoseStatus status, String notes) onRecord;

  @override
  State<DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends State<DoseCard> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // "Omitida" is easy to hit by mistake right next to "Tomada", and it can only be undone
  // within the correction window — so it asks first.
  Future<void> _recordWithConfirmation(DoseStatus status, String notes) async {
    if (status == DoseStatus.skipped) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿No tomó esta dosis?'),
          content: Text(
            'Se registrará ${widget.dose.medicationName} de las '
            '${_formatTime(widget.dose.scheduledAt)} como omitida.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí, omitida'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    widget.onRecord(status, notes);
  }

  Future<void> _openCorrection() async {
    final correction = await showDoseCorrectionSheet(context, widget.dose);
    if (correction != null) widget.onRecord(correction.$1, correction.$2);
  }

  @override
  Widget build(BuildContext context) {
    final dose = widget.dose;

    final onCorrect = dose.correctable && !widget.saving ? _openCorrection : null;

    switch (dose.status) {
      case DoseStatus.taken:
      case DoseStatus.skipped:
        return _HistoryCard(
          dose: dose,
          formatTime: _formatTime,
          saving: widget.saving,
          onCorrect: onCorrect,
        );
      case DoseStatus.missed:
        return _MissedCard(
          dose: dose,
          formatTime: _formatTime,
          saving: widget.saving,
          onCorrect: onCorrect,
        );
      case DoseStatus.pending:
      case DoseStatus.unknown:
        if (!dose.isRecordableAt(widget.now)) {
          // Rounded up, so "1 minuto" really means less than a minute is left.
          final secondsLeft = dose.recordableFrom.difference(widget.now).inSeconds;
          return _UpcomingCard(
            dose: dose,
            formatTime: _formatTime,
            minutesLeft: ((secondsLeft + 59) ~/ 60).clamp(1, 1 << 30),
          );
        }
        return _ActionableCard(
          dose: dose,
          formatTime: _formatTime,
          now: widget.now,
          saving: widget.saving,
          notesController: _notesController,
          onRecord: _recordWithConfirmation,
        );
    }
  }
}

// "Corregir" on an already-resolved dose, while the backend still allows it.
class _CorrectButton extends StatelessWidget {
  const _CorrectButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (onPressed == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Corregir'),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.dose,
    required this.formatTime,
    required this.saving,
    required this.onCorrect,
  });

  final ScheduledDose dose;
  final String Function(DateTime) formatTime;
  final bool saving;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final taken = dose.status == DoseStatus.taken;
    final badgeColor = taken ? AppColors.success : AppColors.warning;
    final borderColor = taken ? AppColors.successSoft : AppColors.warningBgSoft;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIcon(
            color: badgeColor,
            icon: taken ? Icons.check_circle : Icons.close,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleRow(
                  medicationName: dose.medicationName,
                  time: formatTime(dose.scheduledAt),
                ),
                Text(dose.dosage, style: const TextStyle(color: AppColors.textSecondary)),
                if (dose.instructions?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dose.instructions!,
                      style: const TextStyle(
                        color: AppColors.textCaption,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                _Pill(
                  color: taken ? AppColors.successBg : AppColors.warningBg,
                  textColor: taken ? AppColors.success : AppColors.warning,
                  text:
                      '${taken ? '✓ Tomada' : 'Omitida'} a las ${dose.recordedAt != null ? formatTime(dose.recordedAt!) : ''}'
                      '${dose.recordedByName != null ? ' · registrado por ${dose.recordedByName}' : ''}',
                ),
                if (dose.notes?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '"${dose.notes}"',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                _CorrectButton(saving: saving, onPressed: onCorrect),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissedCard extends StatelessWidget {
  const _MissedCard({
    required this.dose,
    required this.formatTime,
    required this.saving,
    required this.onCorrect,
  });

  final ScheduledDose dose;
  final String Function(DateTime) formatTime;
  final bool saving;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dangerBgSoft),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatusIcon(color: AppColors.danger, icon: Icons.warning_amber_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleRow(medicationName: dose.medicationName, time: formatTime(dose.scheduledAt)),
                Text(dose.dosage, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                const _Pill(
                  color: AppColors.dangerBg,
                  textColor: AppColors.dangerStrong,
                  text: 'Perdida — no se registró a tiempo',
                ),
                _CorrectButton(saving: saving, onPressed: onCorrect),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.dose,
    required this.formatTime,
    required this.minutesLeft,
  });

  final ScheduledDose dose;
  final String Function(DateTime) formatTime;
  final int minutesLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceInfo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_bottom, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleRow(medicationName: dose.medicationName, time: formatTime(dose.scheduledAt)),
                Text(dose.dosage, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text(
                  'Disponible en $minutesLeft ${minutesLeft == 1 ? 'minuto' : 'minutos'}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionableCard extends StatelessWidget {
  const _ActionableCard({
    required this.dose,
    required this.formatTime,
    required this.now,
    required this.saving,
    required this.notesController,
    required this.onRecord,
  });

  final ScheduledDose dose;
  final String Function(DateTime) formatTime;
  final DateTime now;
  final bool saving;
  final TextEditingController notesController;
  final void Function(DoseStatus status, String notes) onRecord;

  @override
  Widget build(BuildContext context) {
    final isOverdue = now.isAfter(dose.scheduledAt);
    final minutesOverdue = now.difference(dose.scheduledAt).inMinutes;
    final accent = isOverdue ? AppColors.warning : AppColors.primary;
    final accentDark = isOverdue ? AppColors.warningStrong : const Color(0xFF12798F);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accentDark]),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Text(
              isOverdue ? 'DOSIS ATRASADA' : 'DOSIS PENDIENTE ACTUAL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleRow(
                  medicationName: dose.medicationName,
                  time: formatTime(dose.scheduledAt),
                  showClockIcon: true,
                ),
                Text(dose.dosage, style: const TextStyle(color: AppColors.textSecondary)),
                if (dose.instructions?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dose.instructions!,
                      style: const TextStyle(
                        color: AppColors.textCaption,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (isOverdue)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Atrasada por $minutesOverdue ${minutesOverdue == 1 ? 'minuto' : 'minutos'} — igual puedes registrarla.',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (!dose.withinWindow)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Fuera de la ventana habitual (±45 min) — igual puedes registrarla.',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Observaciones (opcional): ¿cómo le fue con esta toma?',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () => onRecord(DoseStatus.taken, notesController.text),
                        child: saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('✓ Marcar como tomada'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Expanded: the theme's minimumSize is full-width (Size.fromHeight),
                    // which in a Row's unbounded slot fails layout.
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => onRecord(DoseStatus.skipped, notesController.text),
                        child: const Text('✗ Omitida'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.medicationName,
    required this.time,
    this.showClockIcon = false,
  });

  final String medicationName;
  final String time;
  final bool showClockIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            medicationName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        Row(
          children: [
            if (showClockIcon) ...[
              const Icon(Icons.access_time, size: 14, color: AppColors.textCaption),
              const SizedBox(width: 4),
            ],
            Text(
              time,
              style: const TextStyle(
                color: AppColors.textCaption,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.textColor, required this.text});

  final Color color;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
