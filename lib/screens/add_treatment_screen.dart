import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/scanned_medication.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

enum _DurationType { defined, continuous }

class AddTreatmentScreen extends StatefulWidget {
  const AddTreatmentScreen({
    super.key,
    this.profileId,
    this.profileName,
    this.scanned,
    required this.onUnauthenticated,
  });

  // Set when a caregiver adds a treatment for a dependent.
  final String? profileId;
  final String? profileName;
  // Prefills the form with what was read off a prescription photo, for the user to review.
  final ScannedMedication? scanned;
  final Future<void> Function() onUnauthenticated;

  @override
  State<AddTreatmentScreen> createState() => _AddTreatmentScreenState();
}

class _AddTreatmentScreenState extends State<AddTreatmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _medicationController = TextEditingController();
  final _dosageAmountController = TextEditingController();
  final _dosageStrengthController = TextEditingController();
  final _frequencyValueController = TextEditingController(text: '8');
  final _durationDaysController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _totalQuantityController = TextEditingController();
  final _quantityPerDoseController = TextEditingController(text: '1');

  String _frequencyUnit = 'HOURS';
  DateTime _firstDoseAt = _roundToMinute(DateTime.now());
  // False while _firstDoseAt is still the "now" default the form opened with.
  bool _firstDoseAtPicked = false;
  bool _firstDoseAlreadyTaken = false;
  _DurationType? _durationType;
  bool _saving = false;
  String? _error;

  static DateTime _roundToMinute(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  @override
  void initState() {
    super.initState();
    final scanned = widget.scanned;
    if (scanned == null) return;
    // Only what the scan actually read — anything it couldn't stays blank for the user to
    // fill in. Duration is only preset to "defined" when it found a number of days: no
    // number is genuinely ambiguous (continuous? not legible?), so that choice stays open.
    final (amount, strength) = splitDosage(scanned.dosage ?? '');
    _medicationController.text = scanned.medicationName ?? '';
    _dosageAmountController.text = amount;
    _dosageStrengthController.text = strength;
    _frequencyValueController.text = scanned.frequencyHours?.toString() ?? '';
    if (scanned.durationDays != null) {
      _durationType = _DurationType.defined;
      _durationDaysController.text = '${scanned.durationDays}';
    }
  }

  @override
  void dispose() {
    _medicationController.dispose();
    _dosageAmountController.dispose();
    _dosageStrengthController.dispose();
    _frequencyValueController.dispose();
    _durationDaysController.dispose();
    _instructionsController.dispose();
    _totalQuantityController.dispose();
    _quantityPerDoseController.dispose();
    super.dispose();
  }

  Future<void> _pickFirstDoseAt() async {
    final now = DateTime.now();
    final firstDate = _firstDoseAlreadyTaken ? now.subtract(const Duration(days: 365)) : now;
    final lastDate = _firstDoseAlreadyTaken ? now : now.add(const Duration(days: 365));
    // showDatePicker asserts initialDate is inside [firstDate, lastDate] — which
    // stops holding once the "ya se tomó" checkbox flips the allowed range.
    var initialDate = _firstDoseAt;
    if (DateUtils.dateOnly(initialDate).isBefore(DateUtils.dateOnly(firstDate))) initialDate = firstDate;
    if (DateUtils.dateOnly(initialDate).isAfter(DateUtils.dateOnly(lastDate))) initialDate = lastDate;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_firstDoseAt),
    );
    if (time == null) return;

    setState(() {
      _firstDoseAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _firstDoseAtPicked = true;
    });
  }

  // Checking/unchecking "ya se tomó" flips which side of "now" the first dose
  // may be on — pull it back to now if it's left on the wrong side.
  void _onFirstDoseAlreadyTakenChanged(bool value) {
    final now = _roundToMinute(DateTime.now());
    setState(() {
      _firstDoseAlreadyTaken = value;
      if (value ? _firstDoseAt.isAfter(now) : _firstDoseAt.isBefore(now)) _firstDoseAt = now;
    });
  }

  static String? _positiveIntValidator(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Requerido' : null;
    final n = int.tryParse(text);
    if (n == null || n <= 0) return 'Inválido';
    return null;
  }

  // Mirrors the backend's own checks so the user gets a Spanish message here
  // instead of the API's English validation error.
  String? _crossFieldError() {
    if (_durationType == null) {
      return 'Elige si el tratamiento tiene duración definida o es continuo.';
    }
    final now = DateTime.now();
    if (_firstDoseAlreadyTaken && _firstDoseAt.isAfter(now)) {
      return 'Una dosis en el futuro no puede marcarse como ya tomada.';
    }
    if (!_firstDoseAlreadyTaken && _firstDoseAt.isBefore(now.subtract(const Duration(minutes: 1)))) {
      return 'La primera dosis no puede estar en el pasado, salvo que ya se haya tomado.';
    }
    final total = int.tryParse(_totalQuantityController.text.trim());
    final perDose = int.tryParse(_quantityPerDoseController.text.trim()) ?? 1;
    if (total != null && total < perDose) {
      return 'La cantidad suministrada debe alcanzar al menos para una toma.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // The untouched default means "now" — keep it meaning that, instead of it
    // going stale (and rejected as past) while the form was being filled in.
    if (!_firstDoseAtPicked && !_firstDoseAlreadyTaken) {
      _firstDoseAt = _roundToMinute(DateTime.now());
    }
    final crossFieldError = _crossFieldError();
    if (crossFieldError != null) {
      setState(() => _error = crossFieldError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final amount = _dosageAmountController.text.trim();
    final strength = _dosageStrengthController.text.trim();
    final dosage = strength.isNotEmpty ? '$amount ($strength)' : amount;
    final totalQuantity = _totalQuantityController.text.trim();

    final payload = <String, dynamic>{
      'medicationName': _medicationController.text.trim(),
      'dosage': dosage,
      'frequencyValue': int.parse(_frequencyValueController.text.trim()),
      'frequencyUnit': _frequencyUnit,
      'startDate': isoDateTimeWithOffset(_firstDoseAt),
      'firstDoseAlreadyTaken': _firstDoseAlreadyTaken,
      'fromPrescriptionScan': widget.scanned != null,
      if (_durationType == _DurationType.defined)
        'endDate': isoDate(
          _firstDoseAt.add(Duration(days: int.parse(_durationDaysController.text.trim()))),
        ),
      if (_instructionsController.text.trim().isNotEmpty)
        'instructions': _instructionsController.text.trim(),
      if (totalQuantity.isNotEmpty) ...{
        'totalQuantity': int.parse(totalQuantity),
        'quantityPerDose': int.tryParse(_quantityPerDoseController.text.trim()) ?? 1,
      },
    };

    try {
      await ApiClient.createTreatment(payload, profileId: widget.profileId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on UnauthenticatedException {
      if (!mounted) return;
      Navigator.of(context).pop(false);
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar el tratamiento. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          widget.profileName != null ? 'Medicamento para ${widget.profileName}' : 'Agregar medicamento',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              if (widget.scanned != null)
                _ScanReviewNotice(missing: widget.scanned!.missingFields)
              else
                const Text(
                  '¿La fórmula trae más de uno? Repite este formulario para cada medicamento.',
                  style: TextStyle(color: AppColors.textCaption, fontSize: 13),
                ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.dangerStrong, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _Label('Medicamento'),
              TextFormField(
                controller: _medicationController,
                decoration: const InputDecoration(hintText: 'Ej. Losartán'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Cantidad a tomar'),
                        TextFormField(
                          controller: _dosageAmountController,
                          decoration: const InputDecoration(hintText: 'Ej. 1 tableta'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Gramaje (opcional)'),
                        TextFormField(
                          controller: _dosageStrengthController,
                          decoration: const InputDecoration(hintText: 'Ej. 50mg'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Label('Frecuencia'),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _frequencyValueController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '8'),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Inválido';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _frequencyUnit,
                      decoration: const InputDecoration(),
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
                'Ej. "cada 12 horas" y "cada 12 minutos" son cosas muy distintas — elige la unidad con cuidado.',
                style: TextStyle(color: AppColors.textCaption, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _Label('¿Cuándo es (o fue) la primera dosis?'),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _pickFirstDoseAt,
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      // Expanded so a long date (or a large accessibility font size) wraps
                      // instead of overflowing the field.
                      Expanded(child: Text(formatDateTimeShort(_firstDoseAt))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _firstDoseAlreadyTaken,
                      onChanged: (value) => _onFirstDoseAlreadyTakenChanged(value ?? false),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Esta primera dosis ya se tomó a esa hora — quedará registrada como '
                          'tomada y las siguientes se calculan a partir de ahí.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Duración del tratamiento',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ChoiceButton(
                      label: 'Duración definida',
                      selected: _durationType == _DurationType.defined,
                      onTap: () => setState(() => _durationType = _DurationType.defined),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChoiceButton(
                      label: 'Continuo / crónico',
                      selected: _durationType == _DurationType.continuous,
                      onTap: () => setState(() => _durationType = _DurationType.continuous),
                    ),
                  ),
                ],
              ),
              if (_durationType == _DurationType.defined) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _durationDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Ej. 5'),
                        validator: _positiveIntValidator,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'días, como dice la fórmula — "por 5 días"',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              if (_durationType == _DurationType.continuous)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No se generará una fecha de fin — las tomas se siguen programando hasta '
                    'que desactives el tratamiento.',
                    style: TextStyle(color: AppColors.textCaption, fontSize: 12),
                  ),
                ),
              if (_durationType == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Elige una de las dos opciones.',
                    style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              _Label('Instrucciones (opcional)'),
              TextFormField(
                controller: _instructionsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Ej. Tomar con medio vaso de agua después del desayuno',
                ),
              ),
              const SizedBox(height: 16),
              _Label('Cantidad suministrada (opcional)'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _totalQuantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Ej. 30'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => _positiveIntValidator(v, required: false),
                    ),
                  ),
                  if (_totalQuantityController.text.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text('unidades,', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        controller: _quantityPerDoseController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        validator: (v) => _positiveIntValidator(v, required: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('por toma', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Si la sabes, deja de generarse el horario cuando se acabe. Déjalo en blanco '
                'para no llevar el conteo.',
                style: TextStyle(color: AppColors.textCaption, fontSize: 12),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Agregar medicamento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A machine read this off a photo: ask for a careful check, and say what it couldn't read.
class _ScanReviewNotice extends StatelessWidget {
  const _ScanReviewNotice({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: missing.isEmpty ? AppColors.surfaceInfo : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        missing.isEmpty
            ? 'Leído de tu fórmula. Revisa que todo coincida con lo que dice antes de guardar.'
            : 'Leído de tu fórmula. No pudimos leer: ${missing.join(', ')}. Complétalo y revisa '
                'el resto antes de guardar.',
        style: TextStyle(
          color: missing.isEmpty ? AppColors.textSecondary : AppColors.warning,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.4,
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

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
