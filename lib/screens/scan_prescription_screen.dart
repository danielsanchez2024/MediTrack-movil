import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../models/scanned_medication.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';
import 'add_treatment_screen.dart';

typedef PrescriptionScanner = Future<List<ScannedMedication>> Function(Uint8List image);
typedef ImageChooser = Future<Uint8List?> Function(ImageSource source);

enum _Step { capture, scanning, results }

// Photo of a medical prescription → the medications on it, each reviewed and saved one by
// one through the regular "Agregar medicamento" form (so every check that form does still
// applies). Nothing is created until the user confirms each one. Resolves to true when at
// least one treatment was added.
class ScanPrescriptionScreen extends StatefulWidget {
  const ScanPrescriptionScreen({
    super.key,
    this.profileId,
    this.profileName,
    required this.onUnauthenticated,
    this.scanner,
    this.chooseImage,
  });

  final String? profileId;
  final String? profileName;
  final Future<void> Function() onUnauthenticated;
  // Overridable for tests; the real ones call the backend and the camera/gallery.
  final PrescriptionScanner? scanner;
  final ImageChooser? chooseImage;

  @override
  State<ScanPrescriptionScreen> createState() => _ScanPrescriptionScreenState();
}

class _ScanPrescriptionScreenState extends State<ScanPrescriptionScreen> {
  final _picker = ImagePicker();
  _Step _step = _Step.capture;
  Uint8List? _image;
  String? _error;
  List<ScannedMedication> _medications = const [];
  final _added = <int>{};

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
  }

  // Android may kill the app while the camera is open (low memory); the photo taken then
  // isn't lost, it has to be asked for again on the next start.
  Future<void> _recoverLostPhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || widget.chooseImage != null) return;
    final lost = await _picker.retrieveLostData();
    final file = lost.file;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _image = bytes);
  }

  Future<Uint8List?> _defaultChooseImage(ImageSource source) async {
    // The backend downsizes to 1024 px for the model anyway; this keeps the upload small.
    final file = await _picker.pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    return file?.readAsBytes();
  }

  Future<void> _choose(ImageSource source) async {
    try {
      final bytes = await (widget.chooseImage ?? _defaultChooseImage)(source);
      if (bytes != null && mounted) {
        setState(() {
          _image = bytes;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = source == ImageSource.camera
            ? 'No pudimos abrir la cámara. Revisa los permisos de MediTrack o elige una foto de la galería.'
            : 'No pudimos abrir la galería. Revisa los permisos de MediTrack.');
      }
    }
  }

  Future<void> _scan() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _step = _Step.scanning;
      _error = null;
    });
    try {
      final medications = await (widget.scanner ?? ApiClient.scanPrescription)(image);
      if (!mounted) return;
      setState(() {
        _medications = medications;
        _added.clear();
        _step = _Step.results;
      });
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'No pudimos conectar con el servidor. Intenta de nuevo.';
        _step = _Step.capture;
      });
    }
  }

  Future<void> _review(int index) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTreatmentScreen(
          profileId: widget.profileId,
          profileName: widget.profileName,
          scanned: _medications[index],
          onUnauthenticated: widget.onUnauthenticated,
        ),
      ),
    );
    if (created == true && mounted) setState(() => _added.add(index));
  }

  Future<void> _addManually() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTreatmentScreen(
          profileId: widget.profileId,
          profileName: widget.profileName,
          onUnauthenticated: widget.onUnauthenticated,
        ),
      ),
    );
    if (created == true && mounted) {
      // Counts as "something was added" for the caller, without a scanned card to tick.
      setState(() => _added.add(-1));
    }
  }

  void _finish() => Navigator.of(context).pop(_added.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text(widget.profileName != null ? 'Fórmula de ${widget.profileName}' : 'Escanear fórmula'),
        ),
        body: SafeArea(
          child: switch (_step) {
            _Step.capture => _buildCapture(),
            _Step.scanning => _buildScanning(),
            _Step.results => _buildResults(),
          },
        ),
      ),
    );
  }

  Widget _buildCapture() {
    final image = _image;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image == null) ...[
                const Icon(Icons.document_scanner_outlined, size: 44, color: AppColors.primary),
                const SizedBox(height: 10),
                const Text(
                  'Toma una foto de la fórmula médica',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Con buena luz, de frente y con todo el texto visible. Si trae varios '
                  'medicamentos, los detectamos todos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
              ] else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(image, height: 320, fit: BoxFit.contain, semanticLabel: 'Foto de la fórmula'),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _choose(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(image == null ? 'Tomar foto' : 'Otra foto'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _choose(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Galería'),
                    ),
                  ),
                ],
              ),
              if (image != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Leer fórmula'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Honest about where the photo goes: it leaves our servers to be read.
        const Text(
          'Para leerla, la foto se envía a un servicio externo de inteligencia artificial. '
          'Nada se guarda en tus tratamientos hasta que revises y confirmes cada medicamento.',
          style: TextStyle(color: AppColors.textCaption, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _addManually, child: const Text('Prefiero ingresarlo a mano')),
      ],
    );
  }

  Widget _buildScanning() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Leyendo la fórmula…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            SizedBox(height: 6),
            Text(
              'Puede tardar desde unos segundos hasta un par de minutos si tiene varios medicamentos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_medications.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              children: [
                const Icon(Icons.search_off, size: 40, color: AppColors.textMuted),
                const SizedBox(height: 10),
                const Text(
                  'No encontramos medicamentos en la foto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Prueba con otra foto más nítida, o ingrésalo a mano.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _step = _Step.capture),
                  child: const Text('Tomar otra foto'),
                ),
                TextButton(onPressed: _addManually, child: const Text('Ingresarlo a mano')),
              ],
            ),
          ),
        ],
      );
    }

    final pending = _medications.length - _added.where((i) => i >= 0).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          _medications.length == 1
              ? 'Encontramos 1 medicamento'
              : 'Encontramos ${_medications.length} medicamentos',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Revisa cada uno contra la fórmula antes de agregarlo: lo leyó una máquina.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _medications.length; i++) ...[
          _MedicationResult(
            medication: _medications[i],
            added: _added.contains(i),
            onReview: () => _review(i),
          ),
          const SizedBox(height: 12),
        ],
        TextButton.icon(
          onPressed: _addManually,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Falta alguno: agregarlo a mano'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _finish,
          child: Text(pending == 0 ? 'Listo' : 'Terminar (quedan $pending sin agregar)'),
        ),
      ],
    );
  }
}

class _MedicationResult extends StatelessWidget {
  const _MedicationResult({required this.medication, required this.added, required this.onReview});

  final ScannedMedication medication;
  final bool added;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final missing = medication.missingFields;
    final details = [
      if (medication.dosage != null) medication.dosage!,
      if (medication.frequencyHours != null) formatFrequency(medication.frequencyHours!, 'HOURS'),
      if (medication.durationDays != null)
        'por ${medication.durationDays} ${medication.durationDays == 1 ? 'día' : 'días'}',
    ];

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                added ? Icons.check_circle : Icons.medication_outlined,
                color: added ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  medication.medicationName ?? 'Medicamento sin nombre leído',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(details.join(' · '), style: const TextStyle(color: AppColors.textSecondary)),
          ],
          if (missing.isNotEmpty && !added) ...[
            const SizedBox(height: 8),
            Text(
              'No pudimos leer: ${missing.join(', ')}',
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          added
              ? const Text('✓ Agregado a tus tratamientos',
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))
              : FilledButton.tonal(onPressed: onReview, child: const Text('Revisar y agregar')),
        ],
      ),
    );
  }
}
