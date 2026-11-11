import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/notification_preferences.dart';
import '../services/dose_reminders.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_card.dart';

// Mi cuenta > Notificaciones: how the account is reminded of each dose — on
// this phone, by email and by SMS. Saved on the server, so it's the same on
// every phone (and the web shows the email/SMS part too).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.onUnauthenticated});

  final Future<void> Function() onUnauthenticated;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotificationPreferences? _preferences;
  String _email = '';
  bool _hasDependents = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final preferences = await ApiClient.getNotificationPreferences();
      final profile = await ApiClient.getMyProfile();
      // Only decides whether to show the "personas a mi cargo" switch.
      var hasDependents = false;
      try {
        hasDependents = (await ApiClient.getDependents()).isNotEmpty;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _email = profile.email;
        _hasDependents = hasDependents;
      });
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'No pudimos conectar con el servidor.');
    }
  }

  Future<NotificationPreferences> _save(NotificationPreferences wanted) async {
    try {
      return await DoseReminders.save(wanted);
    } on UnauthenticatedException {
      await widget.onUnauthenticated();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Notificaciones')),
      body: SafeArea(
        child: preferences == null
            ? Center(
                child: _loadError == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!, style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
              )
            : NotificationSettingsForm(
                initial: preferences,
                email: _email,
                hasDependents: _hasDependents,
                showPush: DoseReminders.supported,
                onSave: _save,
              ),
      ),
    );
  }
}

// The form itself, separate from the loading so it can be tested on its own.
// onSave returns what was actually saved (push may come back off if the phone
// refused the permission) and throws ApiException on a rejected save.
class NotificationSettingsForm extends StatefulWidget {
  const NotificationSettingsForm({
    super.key,
    required this.initial,
    required this.email,
    required this.hasDependents,
    required this.onSave,
    this.showPush = true,
  });

  final NotificationPreferences initial;
  final String email;
  final bool hasDependents;
  final bool showPush;
  final Future<NotificationPreferences> Function(NotificationPreferences) onSave;

  @override
  State<NotificationSettingsForm> createState() => _NotificationSettingsFormState();
}

class _NotificationSettingsFormState extends State<NotificationSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late NotificationPreferences _value = widget.initial;
  late final _phone = TextEditingController(text: widget.initial.phoneNumber ?? '');
  bool _saving = false;
  String? _saved;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _update(NotificationPreferences value) => setState(() {
        _value = value;
        _saved = null;
      });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phone.text.trim();
    final wanted = NotificationPreferences(
      emailEnabled: _value.emailEnabled,
      emailTiming: _value.emailTiming,
      smsEnabled: _value.smsEnabled,
      smsTiming: _value.smsTiming,
      phoneNumber: phone.isEmpty ? null : phone,
      pushEnabled: _value.pushEnabled,
      pushTiming: _value.pushTiming,
      includeDependents: _value.includeDependents,
    );
    setState(() {
      _saving = true;
      _saved = null;
      _error = null;
    });
    try {
      final saved = await widget.onSave(wanted);
      if (!mounted) return;
      setState(() {
        _value = saved;
        _saved = wanted.pushEnabled && !saved.pushEnabled
            ? 'Cambios guardados, pero el teléfono no permite los avisos de MediTrack. '
                'Actívalos en los ajustes del teléfono y vuelve a intentarlo.'
            : 'Cambios guardados.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on UnauthenticatedException {
      // The screen already sent the user to the login screen.
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar los cambios. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            'Elige cómo quieres que te avisemos de cada toma.',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          if (widget.showPush) ...[
            _ChannelCard(
              icon: Icons.phone_android_outlined,
              title: 'Avisos en el teléfono',
              subtitle: 'Una notificación en este teléfono, aunque la app esté cerrada.',
              enabled: _value.pushEnabled,
              onEnabledChanged: (on) => _update(_value.copyWith(pushEnabled: on)),
              timing: _value.pushTiming,
              onTimingChanged: (t) => _update(_value.copyWith(pushTiming: t)),
            ),
            const SizedBox(height: 12),
          ],
          _ChannelCard(
            icon: Icons.mail_outline,
            title: 'Correo electrónico',
            subtitle: widget.email.isEmpty
                ? 'Tu cuenta no tiene correo. Agrégalo en Mi cuenta para recibirlos.'
                : 'A ${widget.email}',
            enabled: _value.emailEnabled,
            onEnabledChanged: (on) => _update(_value.copyWith(emailEnabled: on)),
            timing: _value.emailTiming,
            onTimingChanged: (t) => _update(_value.copyWith(emailTiming: t)),
          ),
          const SizedBox(height: 12),
          _ChannelCard(
            icon: Icons.sms_outlined,
            title: 'Mensaje de texto (SMS)',
            subtitle: 'Un SMS a tu número de teléfono.',
            enabled: _value.smsEnabled,
            onEnabledChanged: (on) => _update(_value.copyWith(smsEnabled: on)),
            timing: _value.smsTiming,
            onTimingChanged: (t) => _update(_value.copyWith(smsTiming: t)),
            extra: TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(labelText: 'Tu número de teléfono', hintText: 'Ej. +57 300 123 4567'),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return 'Escribe el número al que enviar los SMS';
                return isValidPhone(text) ? null : 'Ingresa un teléfono válido';
              },
            ),
          ),
          if (widget.hasDependents) ...[
            const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: _value.includeDependents,
                  onChanged: (on) => _update(_value.copyWith(includeDependents: on)),
                  secondary: const Icon(Icons.supervisor_account_outlined, color: AppColors.primary),
                  title: const Text('Recibir avisos de las personas a mi cargo',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  subtitle: const Text('Por los mismos medios que elegiste arriba.'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_saved != null) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_saved!,
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

// One channel: an on/off switch and, while it's on, when to be reminded (plus
// anything the channel needs, like the SMS number).
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onEnabledChanged,
    required this.timing,
    required this.onTimingChanged,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final ReminderTiming timing;
  final ValueChanged<ReminderTiming> onTimingChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ListTiles paint on the nearest Material; SectionCard is a plain box.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              value: enabled,
              onChanged: onEnabledChanged,
              secondary: Icon(icon, color: AppColors.primary),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: Text(subtitle),
            ),
          ),
          if (enabled) ...[
            if (extra != null)
              Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: extra),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text('¿Cuándo te avisamos?',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<ReminderTiming>(
                showSelectedIcon: false,
                segments: [
                  for (final t in ReminderTiming.values)
                    ButtonSegment(value: t, label: Text(t.label, textAlign: TextAlign.center)),
                ],
                selected: {timing},
                onSelectionChanged: (selection) => onTimingChanged(selection.single),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
