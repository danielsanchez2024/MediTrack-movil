import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/adherence_summary.dart';
import '../models/scheduled_dose.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/day_selector.dart';
import '../widgets/dose_card.dart';
import '../widgets/section_card.dart';
import '../widgets/add_treatment_choice.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.userName,
    this.profileId,
    required this.onUnauthenticated,
    required this.onViewSos,
    required this.dataVersion,
    required this.onDataChanged,
    this.focusDay,
    this.focusVersion = 0,
  });

  // Whose day this is: the user, or (with profileId) a dependent they care for.
  final String userName;
  final String? profileId;
  final Future<void> Function() onUnauthenticated;
  final VoidCallback onViewSos;
  final int dataVersion;
  final VoidCallback onDataChanged;
  // A tapped reminder's time: Hoy switches to that day (when it's one of the
  // three shown). focusVersion changes on every tap, even for the same day.
  final DateTime? focusDay;
  final int focusVersion;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DayOption _day = DayOption.today;
  List<ScheduledDose>? _doses;
  AdherenceSummary? _summary;
  String? _error;
  bool _loading = true;
  String? _savingDoseId;
  late DateTime _now;
  Timer? _clock;

  static DayOption? _dayFor(DateTime? date) {
    if (date == null) return null;
    for (final option in DayOption.values) {
      final d = dateForDay(option);
      if (d.year == date.year && d.month == date.month && d.day == date.day) return option;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _day = _dayFor(widget.focusDay) ?? DayOption.today;
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void didUpdateWidget(TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusedDay = oldWidget.focusVersion != widget.focusVersion ? _dayFor(widget.focusDay) : null;
    if (focusedDay != null && focusedDay != _day) {
      setState(() => _day = focusedDay);
      _load();
    } else if (oldWidget.dataVersion != widget.dataVersion) {
      _load();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final date = isoDate(dateForDay(_day));
    try {
      final results = await Future.wait([
        ApiClient.getScheduledDoses(date: date, profileId: widget.profileId),
        ApiClient.getAdherenceSummary(date: date, profileId: widget.profileId),
      ]);
      final doses = (results[0] as List<ScheduledDose>)
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      if (!mounted) return;
      setState(() {
        _doses = doses;
        _summary = results[1] as AdherenceSummary;
        _loading = false;
      });
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos conectar con el servidor.';
        _loading = false;
      });
    }
  }

  void _onDayChanged(DayOption day) {
    setState(() => _day = day);
    _load();
  }

  Future<void> _record(ScheduledDose dose, DoseStatus status, String notes) async {
    setState(() => _savingDoseId = dose.id);
    try {
      final updated =
          await ApiClient.updateDoseStatus(dose.id, status, notes, profileId: widget.profileId);
      if (!mounted) return;
      setState(() {
        _doses = _doses!.map((d) => d.id == updated.id ? updated : d).toList();
        _savingDoseId = null;
      });
      // Reloads every tab — including this one's adherence summary, and the
      // remaining supply the Tratamientos tab shows for this treatment.
      widget.onDataChanged();
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _savingDoseId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingDoseId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
      );
    }
  }

  Future<void> _openAddTreatment() async {
    final created = await openAddTreatment(
      context,
      profileId: widget.profileId,
      profileName: widget.profileId != null ? widget.userName : null,
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
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _doses == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _doses == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.wifi_off, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Reintentar'))),
        ],
      );
    }

    final doses = _doses ?? [];
    final groups = <MapEntry<DateTime, List<ScheduledDose>>>[];
    for (final dose in doses) {
      if (groups.isNotEmpty && groups.last.key == dose.scheduledAt) {
        groups.last.value.add(dose);
      } else {
        groups.add(MapEntry(dose.scheduledAt, [dose]));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            // The day being viewed, not always today.
                            formatFullDate(dateForDay(_day)),
                            style: const TextStyle(color: AppColors.textCaption, fontSize: 13),
                          ),
                        ),
                        if (_day == DayOption.today) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.access_time, size: 13, color: AppColors.textMuted),
                          const SizedBox(width: 2),
                          Text(
                            formatTime(_now),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_summary != null) ...[
                    Text(
                      '${_summary!.percentage}%',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_summary!.taken} de ${_summary!.total} tomas',
                      style: const TextStyle(color: AppColors.textCaption, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: widget.onViewSos,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.dangerStrong,
                      side: const BorderSide(color: AppColors.dangerBgSoft),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.shield_outlined, size: 16),
                    label: const Text('Ficha SOS', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceInfo,
            borderRadius: BorderRadius.circular(12),
            border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
          ),
          child: const Text(
            'Para prevenir duplicaciones, las tomas de cada medicamento se registran en orden '
            'cronológico: la siguiente dosis se habilita cuando la anterior ya fue resuelta.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
        DaySelector(value: _day, onChanged: _onDayChanged),
        const SizedBox(height: 16),
        // Doses are created 24 hours ahead, so tomorrow fills in as today goes
        // on — without this, a half-empty "Mañana" looks like missing tomas.
        if (_day == DayOption.tomorrow) ...[
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.textCaption),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aquí ves las tomas de las próximas 24 horas. Las demás de mañana irán '
                  'apareciendo a medida que se acerque la hora.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (doses.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle_outline, size: 36, color: AppColors.textMuted),
                const SizedBox(height: 8),
                Text(
                  _day == DayOption.tomorrow
                      ? 'Todavía no hay tomas programadas para mañana'
                      : 'No hay dosis programadas para este día',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          )
        else
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    formatTime(group.key).toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textCaption,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (group.value.length > 1) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${group.value.length} medicamentos',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Expanded(child: Divider(color: AppColors.border, height: 1)),
                ],
              ),
            ),
            for (final dose in group.value) ...[
              DoseCard(
                key: ValueKey(dose.id),
                dose: dose,
                now: _now,
                saving: _savingDoseId == dose.id,
                onRecord: (status, notes) => _record(dose, status, notes),
              ),
              const SizedBox(height: 12),
            ],
          ],
      ],
    );
  }
}
