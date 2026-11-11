import 'package:flutter/material.dart';

import 'api/token_storage.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/dose_reminders.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DoseReminders.init();
  } catch (_) {
    // Reminders are a convenience — never let them keep the app from starting.
  }
  runApp(const MediTrackApp());
}

class MediTrackApp extends StatelessWidget {
  const MediTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _SessionGate(),
    );
  }
}

// Resumes a stored session instead of always asking to log in again. The
// access token may well have expired while the app was closed — the first API
// call then refreshes it silently (see ApiClient._send), and only if the
// refresh token is gone too does the user land back on the login screen.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<StoredSession?> _session = TokenStorage.readSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoredSession?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snapshot.data;
        return session != null ? HomeShell(userName: session.name) : const LoginScreen();
      },
    );
  }
}
