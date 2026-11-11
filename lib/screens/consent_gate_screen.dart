import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/consent_status.dart';
import '../theme/app_theme.dart';
import '../widgets/section_card.dart';

// Blocks the whole app until the user accepts the currently active health-data
// policy — the mobile counterpart of the web's ConsentGateModal. There's
// deliberately no "decline and continue": accepting this consent is what makes
// storing their health data lawful, so it's either accept or log out.
class ConsentGateScreen extends StatefulWidget {
  const ConsentGateScreen({
    super.key,
    required this.status,
    required this.onAccepted,
    required this.onLogout,
    required this.onUnauthenticated,
  });

  final ConsentStatus status;
  final VoidCallback onAccepted;
  final VoidCallback onLogout;
  final Future<void> Function() onUnauthenticated;

  @override
  State<ConsentGateScreen> createState() => _ConsentGateScreenState();
}

class _ConsentGateScreenState extends State<ConsentGateScreen> {
  bool _checked = false;
  bool _accepting = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await ApiClient.acceptCurrentPrivacyPolicy();
      if (!mounted) return;
      widget.onAccepted();
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos registrar tu aceptación. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _openPolicy(String url) async {
    final opened = await launchUrl(
      ApiClient.resolveServerUrl(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la política.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final contentUrl = status.contentUrl;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Antes de continuar',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Publicamos una nueva versión (${status.version}) de nuestra política de '
                      'tratamiento de datos de salud. Para seguir usando MediTrack necesitamos '
                      'que la leas y la aceptes.',
                      style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                    if (contentUrl != null && contentUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openPolicy(contentUrl),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Leer la política completa'),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.dangerStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // A Material (not a colored Container) so the tile's ink ripple
                    // paints on top of the background instead of underneath it.
                    Material(
                      color: AppColors.surfaceMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        value: _checked,
                        onChanged: (value) => setState(() => _checked = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'He leído y acepto la política de tratamiento de datos de salud, '
                          'versión ${status.version}.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _accepting ? null : widget.onLogout,
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Salir'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _checked && !_accepting ? _accept : null,
                            child: _accepting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Aceptar y continuar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
