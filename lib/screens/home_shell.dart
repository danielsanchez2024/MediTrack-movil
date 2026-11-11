import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/caregiver.dart';
import '../models/consent_status.dart';
import '../models/notification_preferences.dart';
import '../models/scheduled_dose.dart';
import '../services/dose_reminders.dart';
import '../theme/app_theme.dart';
import 'account_screen.dart';
import 'consent_gate_screen.dart';
import 'dependents_screen.dart';
import 'login_screen.dart';
import 'sos_screen.dart';
import 'today_screen.dart';
import 'treatments_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.userName});

  final String userName;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  // Can change from Mi cuenta while the app is open.
  late String _userName = widget.userName;
  // Bumped whenever one tab changes data the others also show (a new treatment,
  // a recorded dose, a deactivation...). Every tab stays alive inside the
  // IndexedStack, so without this they'd keep showing stale data.
  int _dataVersion = 0;

  void _onDataChanged() {
    setState(() => _dataVersion++);
    DoseReminders.sync();
  }

  ReminderHealth _reminderHealth = ReminderHealth.ok;
  // "Ahora no" on the banner hides it until the app is restarted, not forever.
  bool _reminderBannerDismissed = false;
  StreamSubscription<ReminderTap>? _reminderTaps;

  // Set when a reminder was tapped: Hoy jumps to that dose's day. The version
  // changes on every tap, even for the same day.
  DateTime? _focusDay;
  int _focusVersion = 0;

  // Caregiver mode: the profiles this user manages, and whose data the tabs
  // show — null is the user themselves.
  List<ProfileSummary> _dependents = const [];
  String? _activeProfileId;

  ProfileSummary? get _activeDependent {
    for (final d in _dependents) {
      if (d.id == _activeProfileId) return d;
    }
    return null;
  }

  Future<List<ProfileSummary>> _loadDependents() async {
    try {
      final dependents = await ApiClient.getDependents();
      if (mounted) {
        setState(() {
          _dependents = dependents;
          // The profile being viewed was just deleted: back to the user's own.
          if (_activeDependent == null) _activeProfileId = null;
        });
      }
      return dependents;
    } on UnauthenticatedException {
      await _onUnauthenticated();
    } catch (_) {
      // Not being able to list dependents shouldn't block the user's own data.
    }
    return _dependents;
  }

  // Everything that waits until the health-data policy is accepted.
  void _afterConsent() {
    _startReminders();
    _loadDependents();
    _reminderTaps ??= DoseReminders.taps.listen(_handleReminderTap);
    DoseReminders.takePendingTap().then((tap) {
      if (tap != null) _handleReminderTap(tap);
    });
  }

  void _switchProfile(String? profileId) {
    if (profileId == _activeProfileId) return;
    setState(() {
      _activeProfileId = profileId;
      _index = 0;
      _focusDay = null;
    });
  }

  // Tapping a reminder opens Hoy on that person's day; its "Tomada" action
  // also records the doses it was about.
  Future<void> _handleReminderTap(ReminderTap tap) async {
    if (!mounted || _leaving) return;
    final payload = tap.payload;
    var profileId = payload.profileId;
    if (profileId != null && !_dependents.any((d) => d.id == profileId)) {
      final dependents = await _loadDependents();
      if (!mounted) return;
      // No longer someone this user looks after: fall back to their own day.
      if (!dependents.any((d) => d.id == profileId)) profileId = null;
    }
    setState(() {
      _activeProfileId = profileId;
      _index = 0;
      _focusDay = payload.at;
      _focusVersion++;
    });

    if (!tap.markTaken || payload.doseIds.isEmpty) return;
    var recorded = 0;
    String? failure;
    for (final id in payload.doseIds) {
      try {
        await ApiClient.updateDoseStatus(id, DoseStatus.taken, null, profileId: profileId);
        recorded++;
      } on UnauthenticatedException {
        await _onUnauthenticated();
        return;
      } on ApiException catch (e) {
        failure = e.message;
      } catch (_) {
        failure = 'No pudimos conectar con el servidor.';
      }
    }
    if (!mounted) return;
    if (recorded > 0) _onDataChanged();
    final message = failure == null
        ? (recorded == 1 ? 'Dosis registrada como tomada.' : '$recorded dosis registradas como tomadas.')
        : 'No se pudo registrar desde el aviso: $failure Puedes marcarla aquí.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDependents() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DependentsScreen(
          dependents: _dependents,
          onChanged: () async {
            final list = await _loadDependents();
            DoseReminders.sync();
            return list;
          },
          onUnauthenticated: _onUnauthenticated,
        ),
      ),
    );
  }

  Future<void> _showProfilePicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceCard,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('¿De quién quieres ver la medicación?',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            _ProfileOption(
              name: _userName,
              subtitle: 'Mi perfil',
              selected: _activeProfileId == null,
              onTap: () => Navigator.of(context).pop('me'),
            ),
            for (final d in _dependents)
              _ProfileOption(
                name: d.name,
                subtitle: d.claimed ? 'Tiene su propia cuenta' : 'Lo gestionas tú',
                selected: _activeProfileId == d.id,
                onTap: () => Navigator.of(context).pop(d.id),
              ),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.group_add_outlined, color: AppColors.primary),
              title: Text(_dependents.isEmpty ? 'Agregar a alguien que cuido' : 'Gestionar perfiles que cuido'),
              onTap: () => Navigator.of(context).pop('manage'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'manage') {
      _openDependents();
    } else {
      _switchProfile(choice == 'me' ? null : choice);
    }
  }

  // Null while still checking. The tabs aren't built until then, so none of
  // them loads health data behind a policy the user hasn't accepted yet.
  ConsentStatus? _consent;
  bool _consentChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConsent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderTaps?.cancel();
    super.dispose();
  }

  bool get _showingTabs => _consentChecked && !(_consent?.requiresAcceptance ?? false);

  // Coming back to the app (e.g. from tapping a reminder): refresh every tab
  // and the reminders, since doses may have been recorded elsewhere meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _showingTabs && !_leaving) {
      _onDataChanged();
      // The user may have just allowed (or blocked) notifications/alarms in
      // the system settings.
      _refreshReminderHealth();
    }
  }

  Future<void> _refreshReminderHealth() async {
    if (!DoseReminders.supported) return;
    final health = await DoseReminders.health();
    if (!mounted) return;
    setState(() => _reminderHealth = health);
  }

  // Said before the system dialog, so the request doesn't come out of nowhere.
  Future<bool> _explainReminders() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined, color: AppColors.primary),
        title: const Text('¿Te avisamos a la hora de cada toma?'),
        content: const Text(
          'MediTrack te enviará un aviso en este teléfono cuando toque tomar un medicamento '
          '(también de las personas que cuidas). A continuación el teléfono te pedirá permiso. '
          'Puedes cambiarlo cuando quieras en Mi cuenta > Notificaciones.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sí, avisarme')),
        ],
      ),
    );
    return accepted == true;
  }

  void _showBlockedHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No se pudieron activar: permite las notificaciones de MediTrack en los '
          'ajustes del teléfono.'),
    ));
  }

  // The account's preferences decide (Mi cuenta > Notificaciones); the first
  // time on this phone the OS permission is asked, explained beforehand.
  Future<void> _startReminders() async {
    if (!DoseReminders.supported) return;
    final preferences = await DoseReminders.refreshPreferences();
    if (preferences != null && await DoseReminders.needsPermissionPrompt(preferences) && mounted) {
      final wanted = await _explainReminders();
      final granted = wanted && await DoseReminders.requestPermission();
      if (!granted) {
        // "Ahora no" (or the OS refused): push stays off for the account until
        // they turn it on again, so nothing pretends to be reminding them.
        try {
          await DoseReminders.save(preferences.copyWith(pushEnabled: false));
        } catch (_) {}
        if (wanted) _showBlockedHint();
      }
    }
    DoseReminders.sync();
    _refreshReminderHealth();
  }

  // The banner's button: turn reminders on, ask for the notification
  // permission again, or (Android) allow exact alarms.
  Future<void> _fixReminders() async {
    switch (_reminderHealth) {
      case ReminderHealth.inexact:
        await DoseReminders.requestExactAlarms();
      case ReminderHealth.blocked:
        if (await DoseReminders.requestPermission()) {
          DoseReminders.sync();
        } else {
          _showBlockedHint();
        }
      case ReminderHealth.off:
        await _enableReminders();
      case ReminderHealth.ok:
        break;
    }
    await _refreshReminderHealth();
  }

  Future<void> _enableReminders() async {
    if (!await _explainReminders()) return;
    final current = await DoseReminders.cachedPreferences() ?? const NotificationPreferences();
    try {
      final saved = await DoseReminders.save(current.copyWith(pushEnabled: true));
      if (!saved.pushEnabled) _showBlockedHint();
    } on UnauthenticatedException {
      await _onUnauthenticated();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pudimos guardar el cambio. Revisa tu conexión e inténtalo de nuevo.'),
      ));
    }
  }

  Future<void> _checkConsent() async {
    try {
      final status = await ApiClient.getConsentStatus();
      if (!mounted) return;
      setState(() {
        _consent = status;
        _consentChecked = true;
      });
      if (!status.requiresAcceptance) _afterConsent();
    } on UnauthenticatedException {
      await _onUnauthenticated();
    } catch (_) {
      // Fails open, same as the web: an outage (or no active policy
      // configured) shouldn't lock everyone out of their own medication.
      if (mounted) setState(() => _consentChecked = true);
      _afterConsent();
    }
  }

  // Several tabs can hit an expired session at the same moment — only the
  // first one should navigate away.
  bool _leaving = false;

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Mientras no vuelvas a entrar, este teléfono no te avisará de las tomas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmed == true) await _logout();
  }

  Future<void> _logout() async {
    if (_leaving) return;
    _leaving = true;
    await DoseReminders.forgetAccount();
    await ApiClient.logout();
    _goToLogin(sessionExpired: false);
  }

  // ApiClient already cleared the stored session by the time this is called.
  Future<void> _onUnauthenticated() async {
    if (_leaving) return;
    _leaving = true;
    await DoseReminders.forgetAccount();
    _goToLogin(sessionExpired: true);
  }

  void _goToLogin({required bool sessionExpired, String? notice}) {
    if (!mounted) return;
    // pushAndRemoveUntil: this can be reached from a screen pushed on top (Mi cuenta).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(sessionExpired: sessionExpired, notice: notice),
      ),
      (_) => false,
    );
  }

  Future<void> _onAccountDeleted() async {
    if (_leaving) return;
    _leaving = true;
    await DoseReminders.forgetAccount();
    _goToLogin(sessionExpired: false, notice: 'Tu cuenta fue eliminada.');
  }

  void _openAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          onNameChanged: (name) => setState(() => _userName = name),
          onAccountDeleted: _onAccountDeleted,
          onUnauthenticated: _onUnauthenticated,
        ),
      ),
    // The notification preferences may have changed in there.
    ).then((_) => _refreshReminderHealth());
  }

  @override
  Widget build(BuildContext context) {
    if (!_consentChecked) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final consent = _consent;
    if (consent != null && consent.requiresAcceptance) {
      return ConsentGateScreen(
        status: consent,
        onAccepted: () {
          setState(() => _consent = null);
          _afterConsent();
        },
        onLogout: _logout,
        onUnauthenticated: _onUnauthenticated,
      );
    }

    final dependent = _activeDependent;
    final profileId = dependent?.id;
    final profileName = dependent?.name;
    // Keyed by profile: switching recreates each tab, so nothing from the
    // previous person's data (an open edit form, a cached history) carries over.
    final profileKey = profileId ?? 'me';
    final screens = [
      TodayScreen(
        key: ValueKey('today-$profileKey'),
        userName: profileName ?? _userName,
        profileId: profileId,
        onUnauthenticated: _onUnauthenticated,
        onViewSos: () => setState(() => _index = 2),
        dataVersion: _dataVersion,
        onDataChanged: _onDataChanged,
        focusDay: _focusDay,
        focusVersion: _focusVersion,
      ),
      TreatmentsScreen(
        key: ValueKey('treatments-$profileKey'),
        profileId: profileId,
        profileName: profileName,
        onUnauthenticated: _onUnauthenticated,
        dataVersion: _dataVersion,
        onDataChanged: _onDataChanged,
      ),
      SosScreen(
        key: ValueKey('sos-$profileKey'),
        profileId: profileId,
        onUnauthenticated: _onUnauthenticated,
        dataVersion: _dataVersion,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        // Tapping the title switches whose medication the tabs show.
        title: InkWell(
          onTap: _showProfilePicker,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    gradient: AppGradients.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MediTrack'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              profileName ?? _userName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textCaption,
                              ),
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 16, color: AppColors.textCaption),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openAccount,
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mi cuenta',
          ),
          IconButton(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (profileName != null)
            _ManagingBanner(name: profileName, onBack: () => _switchProfile(null)),
          if (_index == 0 && _reminderHealth != ReminderHealth.ok && !_reminderBannerDismissed)
            _RemindersBanner(
              health: _reminderHealth,
              onFix: _fixReminders,
              onDismiss: () => setState(() => _reminderBannerDismissed = true),
            ),
          Expanded(child: IndexedStack(index: _index, children: screens)),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            backgroundColor: AppColors.surfaceCard,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today, color: AppColors.primary),
                label: 'Hoy',
              ),
              NavigationDestination(
                icon: Icon(Icons.medication_outlined),
                selectedIcon: Icon(Icons.medication, color: AppColors.primary),
                label: 'Tratamientos',
              ),
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield, color: AppColors.primary),
                label: 'SOS',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: selected ? AppColors.primary : AppColors.surfaceInfo,
        child: Icon(Icons.person_outline, color: selected ? Colors.white : AppColors.primary),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check, color: AppColors.primary) : null,
    );
  }
}

// Always visible while acting on someone else's data, so a dose never gets
// recorded on the wrong person by accident.
class _ManagingBanner extends StatelessWidget {
  const _ManagingBanner({required this.name, required this.onBack});

  final String name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            const Icon(Icons.supervisor_account_outlined, size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Estás gestionando el perfil de $name',
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            TextButton(onPressed: onBack, child: const Text('Volver al mío')),
          ],
        ),
      ),
    );
  }
}

// On Hoy whenever reminders won't reach the user (turned off, notifications
// blocked, or Android only allowing late alarms), with the button that fixes it.
class _RemindersBanner extends StatelessWidget {
  const _RemindersBanner({required this.health, required this.onFix, required this.onDismiss});

  final ReminderHealth health;
  final VoidCallback onFix;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final inexact = health == ReminderHealth.inexact;
    final blocked = health == ReminderHealth.blocked;
    return Material(
      color: AppColors.surfaceInfo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              inexact ? Icons.alarm_off_outlined : Icons.notifications_off_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                inexact
                    ? 'Los avisos pueden llegar con retraso. Permite las alarmas para que lleguen a la hora exacta.'
                    : blocked
                        ? 'El teléfono no deja que MediTrack te avise de las tomas.'
                        : 'Los avisos de tomas en este teléfono están apagados.',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            TextButton(onPressed: onFix, child: Text(inexact || blocked ? 'Permitir' : 'Activar')),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Ahora no',
            ),
          ],
        ),
      ),
    );
  }
}
