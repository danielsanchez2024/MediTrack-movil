import 'package:flutter/material.dart';

import '../screens/add_treatment_screen.dart';
import '../screens/scan_prescription_screen.dart';
import '../theme/app_theme.dart';

// What the "Agregar" buttons open: scan a prescription or type it in. Resolves to true when
// a treatment was created either way, so the caller can refresh.
Future<bool> openAddTreatment(
  BuildContext context, {
  String? profileId,
  String? profileName,
  required Future<void> Function() onUnauthenticated,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceCard,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined, color: AppColors.primary),
            title: const Text('Escanear fórmula', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Toma una foto y revisa lo que detectemos'),
            onTap: () => Navigator.of(context).pop('scan'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note, color: AppColors.primary),
            title: const Text('Ingresar a mano', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Escribe el medicamento, la dosis y la frecuencia'),
            onTap: () => Navigator.of(context).pop('manual'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;

  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => choice == 'scan'
          ? ScanPrescriptionScreen(
              profileId: profileId,
              profileName: profileName,
              onUnauthenticated: onUnauthenticated,
            )
          : AddTreatmentScreen(
              profileId: profileId,
              profileName: profileName,
              onUnauthenticated: onUnauthenticated,
            ),
    ),
  );
  return created == true;
}
