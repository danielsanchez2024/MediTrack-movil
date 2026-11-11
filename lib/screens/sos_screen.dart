import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/emergency_card.dart';
import '../theme/app_theme.dart';
import '../widgets/allergy_sheet.dart';
import '../widgets/emergency_contact_sheet.dart';
import '../widgets/section_card.dart';

const _severityStyle = {
  'SEVERE': (AppColors.dangerBg, AppColors.dangerStrong),
  'MODERATE': (AppColors.warningBg, AppColors.warning),
  'MILD': (AppColors.surfaceMuted, AppColors.textSecondary),
};

class SosScreen extends StatefulWidget {
  const SosScreen({
    super.key,
    this.profileId,
    required this.onUnauthenticated,
    required this.dataVersion,
  });

  // Set when a caregiver is looking at a dependent's card.
  final String? profileId;
  final Future<void> Function() onUnauthenticated;
  final int dataVersion;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  EmergencyCard? _card;
  // Loaded separately from the card: the card's own allergy list has no ids,
  // which editing needs.
  List<EmergencyAllergy> _allergies = const [];
  String? _error;
  bool _sharingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataVersion != widget.dataVersion) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        ApiClient.getEmergencyCard(profileId: widget.profileId),
        ApiClient.getAllergies(profileId: widget.profileId),
      ]);
      if (!mounted) return;
      setState(() {
        _card = results[0] as EmergencyCard;
        _allergies = results[1] as List<EmergencyAllergy>;
      });
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

  Future<void> _editContact() async {
    final card = _card!;
    final saved = await showEmergencyContactSheet(
      context,
      currentName: card.emergencyContactName,
      currentPhone: card.emergencyContactPhone,
      profileId: widget.profileId,
      onUnauthenticated: widget.onUnauthenticated,
    );
    if (saved == true) _load();
  }

  Future<void> _editAllergy([EmergencyAllergy? existing]) async {
    final result = await showAllergySheet(
      context,
      existing: existing,
      profileId: widget.profileId,
      onUnauthenticated: widget.onUnauthenticated,
    );
    if (result == null || !mounted) return;
    setState(() {
      _allergies = switch (result) {
        AllergySaved(:final allergy) when existing == null => [..._allergies, allergy],
        AllergySaved(:final allergy) =>
          _allergies.map((a) => a.id == allergy.id ? allergy : a).toList(),
        AllergyDeleted() => _allergies.where((a) => a.id != existing?.id).toList(),
      };
    });
  }

  // Opens the system share sheet, so the PDF can be saved, printed or sent
  // (WhatsApp, email…) from wherever the user needs it.
  Future<void> _sharePdf() async {
    setState(() => _sharingPdf = true);
    try {
      final bytes = await ApiClient.getEmergencyCardPdf(profileId: widget.profileId);
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'ficha-emergencia.pdf')],
        fileNameOverrides: const ['ficha-emergencia.pdf'],
        title: 'Ficha SOS',
      ));
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException ? e.message : 'No pudimos generar el PDF.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _sharingPdf = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    var launched = false;
    try {
      launched = await canLaunchUrl(uri) && await launchUrl(uri);
    } catch (_) {}
    // In an emergency a silent failure is the worst outcome: say so, and show
    // the number so it can be dialed by hand.
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('No se pudo abrir el marcador. Llama manualmente al $phone.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_card == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _card == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Reintentar'))),
        ],
      );
    }

    final card = _card!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.dangerStrong),
            const SizedBox(width: 8),
            const Text(
              'Ficha SOS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(card.name, style: const TextStyle(color: AppColors.textCaption)),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                title: 'Contactos',
                actionLabel: card.emergencyContactName != null ? 'Editar' : 'Agregar',
                actionIcon: card.emergencyContactName != null ? Icons.edit_outlined : Icons.add,
                onAction: _editContact,
              ),
              const SizedBox(height: 12),
              if (card.emergencyContactName != null)
                _ContactTile(
                  name: card.emergencyContactName!,
                  subtitle: 'Contacto de emergencia',
                  phone: card.emergencyContactPhone,
                  danger: false,
                  onCall: card.emergencyContactPhone != null
                      ? () => _call(card.emergencyContactPhone!)
                      : null,
                )
              else
                const Text(
                  'No hay un contacto de emergencia registrado.',
                  style: TextStyle(color: AppColors.textCaption),
                ),
              const SizedBox(height: 8),
              _ContactTile(
                name: 'Línea Nacional de Urgencias',
                subtitle: null,
                phone: '123',
                danger: true,
                onCall: () => _call('123'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                title: 'Alergias clínicas',
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.dangerStrong, size: 18),
                actionLabel: 'Agregar',
                actionIcon: Icons.add,
                onAction: _editAllergy,
              ),
              const SizedBox(height: 12),
              if (_allergies.isEmpty)
                const Text('Sin alergias registradas.', style: TextStyle(color: AppColors.textCaption))
              else ...[
                for (final allergy in _allergies) ...[
                  _AllergyRow(
                    key: ValueKey(allergy.id),
                    allergy: allergy,
                    onTap: () => _editAllergy(allergy),
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'Toca una alergia para editarla o eliminarla.',
                  style: TextStyle(color: AppColors.textCaption, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tratamientos activos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 12),
              if (card.activeTreatments.isEmpty)
                const Text('Sin tratamientos activos.', style: TextStyle(color: AppColors.textCaption))
              else
                for (final treatment in card.activeTreatments) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.medication_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${treatment.medicationName} — ${treatment.dosage}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _sharingPdf ? null : _sharePdf,
          icon: _sharingPdf
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(_sharingPdf ? 'Generando PDF…' : 'Descargar o compartir PDF'),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.name,
    required this.subtitle,
    required this.phone,
    required this.danger,
    required this.onCall,
  });

  final String name;
  final String? subtitle;
  final String? phone;
  final bool danger;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger ? AppColors.dangerBg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onCall,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: danger ? AppColors.dangerBgSoft : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.dangerStrong : AppColors.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: const TextStyle(color: AppColors.textCaption, fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                Icons.call,
                size: 18,
                color: danger ? AppColors.dangerStrong : AppColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.leading,
  });

  final String title;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        TextButton.icon(
          onPressed: onAction,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: Icon(actionIcon, size: 16),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _AllergyRow extends StatelessWidget {
  const _AllergyRow({super.key, required this.allergy, required this.onTap});

  final EmergencyAllergy allergy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, color) =
        _severityStyle[allergy.severity] ?? (AppColors.surfaceMuted, AppColors.textSecondary);
    final label = allergySeverityLabels[allergy.severity] ?? allergy.severity;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(allergy.description, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
