import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../api/api_client.dart';
import '../models/caregiver.dart';
import '../models/notification_preferences.dart';
import '../models/scheduled_dose.dart';
import '../models/treatment.dart';

// What a reminder carries so tapping it can land on the right person and day,
// and so its "Tomada" action knows which doses to record.
class ReminderPayload {
  ReminderPayload({required this.at, this.profileId, this.doseIds = const []});

  factory ReminderPayload.fromJson(Map<String, dynamic> json) => ReminderPayload(
        at: DateTime.parse(json['at'] as String),
        profileId: json['profileId'] as String?,
        doseIds: (json['doseIds'] as List? ?? const []).cast<String>(),
      );

  // Null on a malformed/foreign payload — tapping it then just opens the app.
  static ReminderPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return ReminderPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  final DateTime at;
  // Null: the user's own doses; otherwise the dependent they're for.
  final String? profileId;
  // Only real backend doses — empty when the reminder is (partly) a projection.
  final List<String> doseIds;

  String encode() => jsonEncode({
        'at': at.toIso8601String(),
        if (profileId != null) 'profileId': profileId,
        'doseIds': doseIds,
      });
}

// The user tapped a reminder (markTaken: false) or its "Tomada" action.
class ReminderTap {
  ReminderTap(this.payload, {required this.markTaken});

  final ReminderPayload payload;
  final bool markTaken;
}

// One local notification: every pending dose due at the same minute is folded
// into a single reminder instead of buzzing once per medication.
class PlannedReminder {
  PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final ReminderPayload payload;

  // "Tomada" from the notification only makes sense when every dose in it
  // already exists on the backend (a projection has nothing to record yet).
  bool get canMarkTaken => payload.doseIds.isNotEmpty;
}

const _projectedIdPrefix = 'projected:';

bool _isProjected(ScheduledDose dose) => dose.id.startsWith(_projectedIdPrefix);

// How long before a dose the "10 min antes" reminder fires — the same moment
// the backend starts letting the dose be recorded (and sends its own email).
const upcomingReminderLead = Duration(minutes: 10);

// Pure so it can be unit tested: which reminders the given doses call for.
// forName/slot are for a dependent's doses (caregiver mode): the reminder names
// them, and slot keeps its id apart from the user's own reminder at the same
// minute. profileId goes into the payload so a tap opens that person's day.
// timing (the account's push preference) decides between a reminder on time,
// one 10 minutes before, or both.
@visibleForTesting
List<PlannedReminder> planReminders(
  List<ScheduledDose> doses,
  DateTime now, {
  String? forName,
  int slot = 0,
  String? profileId,
  ReminderTiming timing = ReminderTiming.atTime,
}) {
  final byMinute = <DateTime, List<ScheduledDose>>{};
  for (final dose in doses) {
    if (dose.status != DoseStatus.pending || !dose.scheduledAt.isAfter(now)) continue;
    final at = dose.scheduledAt;
    final minute = DateTime(at.year, at.month, at.day, at.hour, at.minute);
    byMinute.putIfAbsent(minute, () => []).add(dose);
  }

  // Stable per minute, kind and profile, so re-planning overwrites instead of
  // duplicating. Low 6 bits: the profile slot (0 = the user themselves); bit 6:
  // the "10 min antes" reminder of that same minute.
  int idFor(DateTime minute, {required bool early}) =>
      ((((minute.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute) & 0xffffff) << 7) |
          (early ? 0x40 : 0) |
          (slot & 0x3f)) &
      0x7fffffff;

  final minutes = byMinute.keys.toList()..sort();
  final reminders = <PlannedReminder>[];
  for (final minute in minutes) {
    final group = byMinute[minute]!;
    final body = group.length == 1
        ? '${group.first.medicationName} — ${group.first.dosage}'
        : group.map((d) => d.medicationName).join(', ');
    final payload = ReminderPayload(
      at: minute,
      profileId: profileId,
      doseIds: group.any(_isProjected) ? const [] : [for (final d in group) d.id],
    );
    final early = minute.subtract(upcomingReminderLead);
    if (timing.includesBefore && early.isAfter(now)) {
      reminders.add(PlannedReminder(
        id: idFor(minute, early: true),
        at: early,
        title: forName != null
            ? 'En 10 minutos: medicación de $forName'
            : 'En 10 minutos: tu medicación',
        body: body,
        payload: payload,
      ));
    }
    if (timing.includesAtTime) {
      reminders.add(PlannedReminder(
        id: idFor(minute, early: false),
        at: minute,
        title: forName != null ? 'Hora de la medicación de $forName' : 'Hora de tu medicación',
        body: body,
        payload: payload,
      ));
    }
  }
  return reminders;
}

// One dependent's doses, for buildReminders.
typedef DependentDoses = ({ProfileSummary profile, List<ScheduledDose> doses});

// Everything to schedule for this account, following its push preferences:
// nothing when push is off, the people in their care only if includeDependents,
// soonest first and capped at what the platform keeps pending.
@visibleForTesting
List<PlannedReminder> buildReminders(
  NotificationPreferences preferences,
  List<ScheduledDose> own,
  List<DependentDoses> dependents,
  DateTime now,
) {
  if (!preferences.pushEnabled) return const [];
  final reminders = planReminders(own, now, timing: preferences.pushTiming);
  if (preferences.includeDependents) {
    for (var i = 0; i < dependents.length; i++) {
      reminders.addAll(planReminders(
        dependents[i].doses,
        now,
        forName: dependents[i].profile.name,
        slot: i + 1,
        profileId: dependents[i].profile.id,
        timing: preferences.pushTiming,
      ));
    }
  }
  reminders.sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(maxPendingReminders).toList();
}

const _minutesPerUnit = {'MINUTES': 1, 'HOURS': 60, 'DAYS': 60 * 24};

// PROJECTIONS, not real doses: the backend only generates doses 24h ahead
// (topped up hourly), so a phone that isn't opened for a day would run out of
// reminders. This extends each active treatment's rhythm (startDate + k ×
// frequency, the same grid ScheduledDoseService uses) past the last dose the
// backend already returned, up to `horizon` from now. They're only used to
// schedule reminders — never shown as doses or recorded — and get replaced by
// the real ones on the next sync. Stops at the end date and, for a tracked
// supply, after as many doses as are left (remainingQuantity already counts the
// doses the backend generated).
@visibleForTesting
List<ScheduledDose> projectDoses(
  List<Treatment> treatments,
  List<ScheduledDose> fetched,
  DateTime now, {
  Duration horizon = const Duration(days: 3),
}) {
  final until = now.add(horizon);
  final projected = <ScheduledDose>[];
  for (final t in treatments) {
    final start = t.startDate;
    final unitMinutes = _minutesPerUnit[t.frequencyUnit];
    if (!t.active || start == null || t.frequencyValue == null || unitMinutes == null) continue;
    final step = Duration(minutes: t.frequencyValue! * unitMinutes);
    if (step.inMinutes <= 0) continue;

    final own = fetched.where((d) => d.treatmentId == t.id).toList();
    // A tracked supply with nothing generated means it already ran out.
    if (t.remainingQuantity != null && own.isEmpty) continue;
    var allowed = t.remainingQuantity != null
        ? t.remainingQuantity! ~/ ((t.quantityPerDose ?? 1) <= 0 ? 1 : (t.quantityPerDose ?? 1))
        : 1 << 30;

    var after = now;
    for (final d in own) {
      if (d.scheduledAt.isAfter(after)) after = d.scheduledAt;
    }
    final end = t.endDate != null
        ? DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day, 23, 59)
        : null;

    final elapsed = after.difference(start).inMinutes;
    var k = elapsed < 0 ? 0 : elapsed ~/ step.inMinutes + 1;
    var cursor = start.add(step * k);
    while (!cursor.isAfter(until) && allowed > 0 && (end == null || !cursor.isAfter(end))) {
      projected.add(ScheduledDose(
        id: '$_projectedIdPrefix${t.id}:${cursor.millisecondsSinceEpoch}',
        treatmentId: t.id,
        medicationName: t.medicationName,
        dosage: t.dosage,
        instructions: t.instructions,
        scheduledAt: cursor,
        status: DoseStatus.pending,
        recordedAt: null,
        notes: null,
        recordedByName: null,
        withinWindow: true,
        recordable: false,
      ));
      allowed--;
      k++;
      cursor = start.add(step * k);
    }
  }
  return projected;
}

// iOS keeps at most 64 pending local notifications (Android's alarm limit is
// higher); the soonest ones win, and every sync tops the list up again.
const maxPendingReminders = 60;

// Whether reminders will actually reach the user — drives the banner on Hoy.
// off: the account turned push off; blocked: this phone doesn't allow
// MediTrack's notifications; inexact: Android only allows late alarms.
enum ReminderHealth { ok, off, blocked, inexact }

// Local dose reminders, rebuilt from the backend's schedule (plus projections,
// see projectDoses) whenever the app learns something changed (see HomeShell).
class DoseReminders {
  DoseReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _storage = FlutterSecureStorage();
  // The account's preferences as last seen, so reminders can be rebuilt (and
  // the banner decided) offline.
  static const _preferencesKey = 'notification_preferences';
  // Whether this phone already asked the OS for permission: 'true'/'false' is
  // what the user answered (the system dialog only shows once per install).
  static const _permissionKey = 'reminders_permission';
  // Before the preferences lived on the server, each phone kept its own on/off.
  static const _legacyEnabledKey = 'reminders_enabled';
  static const _takenActionId = 'taken';
  static const _iosCategory = 'dose_reminder';

  static const _androidChannel = (
    id: 'dose_reminders',
    name: 'Recordatorios de dosis',
    description: 'Avisa cuando toca tomar un medicamento',
  );

  static NotificationDetails _detailsFor(PlannedReminder reminder) => NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // Opens the app (showsUserInterface) and records it there, in the
          // foreground with the normal session — a background isolate has no
          // safe access to the stored tokens/refresh flow.
          actions: reminder.canMarkTaken
              ? const [AndroidNotificationAction(_takenActionId, 'Tomada', showsUserInterface: true)]
              : null,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: reminder.canMarkTaken ? _iosCategory : null,
        ),
      );

  static bool _initialized = false;

  // The web app has its own browser notifications; desktop isn't a target.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static final _taps = StreamController<ReminderTap>.broadcast();
  static ReminderTap? _pendingTap;
  static bool _launchChecked = false;

  // Taps while the app is running (HomeShell listens once the tabs are up).
  static Stream<ReminderTap> get taps => _taps.stream;

  static void _onResponse(NotificationResponse response) {
    final payload = ReminderPayload.tryParse(response.payload);
    if (payload == null) return;
    final tap = ReminderTap(payload, markTaken: response.actionId == _takenActionId);
    if (_taps.hasListener) {
      _taps.add(tap);
    } else {
      // e.g. still on the login/consent screen: handed over once HomeShell is ready.
      _pendingTap = tap;
    }
  }

  // The tap that launched (or is waiting for) HomeShell, handed out only once.
  static Future<ReminderTap?> takePendingTap() async {
    if (!supported) return null;
    var tap = _pendingTap;
    _pendingTap = null;
    if (tap == null && !_launchChecked) {
      _launchChecked = true;
      try {
        await init();
        final details = await _plugin.getNotificationAppLaunchDetails();
        final response = details?.notificationResponse;
        if (details?.didNotificationLaunchApp == true && response != null) {
          final payload = ReminderPayload.tryParse(response.payload);
          if (payload != null) tap = ReminderTap(payload, markTaken: response.actionId == _takenActionId);
        }
      } catch (_) {}
    }
    return tap;
  }

  static Future<void> init() async {
    if (!supported || _initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Asked for explicitly in requestPermission, not at startup.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _iosCategory,
              actions: [
                DarwinNotificationAction.plain(
                  _takenActionId,
                  'Tomada',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _initialized = true;
  }

  static Future<NotificationPreferences?> cachedPreferences() async {
    try {
      final raw = await _storage.read(key: _preferencesKey);
      if (raw == null) return null;
      return NotificationPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cache(NotificationPreferences preferences) =>
      _storage.write(key: _preferencesKey, value: jsonEncode(preferences.toJson()));

  // Fresh from the server (and cached); the cached copy when offline. A phone
  // that had reminders turned off back when that was a per-phone switch carries
  // that choice over to the account once.
  static Future<NotificationPreferences?> refreshPreferences() async {
    try {
      var preferences = await ApiClient.getNotificationPreferences();
      final legacy = await _storage.read(key: _legacyEnabledKey);
      if (legacy != null) {
        if (legacy == 'false' && preferences.pushEnabled) {
          preferences = await ApiClient.updateNotificationPreferences(
              preferences.copyWith(pushEnabled: false));
        }
        await _storage.write(key: _permissionKey, value: legacy);
        await _storage.delete(key: _legacyEnabledKey);
      }
      await _cache(preferences);
      return preferences;
    } catch (_) {
      return cachedPreferences();
    }
  }

  // The account wants reminders on its phones but this one never asked the OS
  // yet — HomeShell explains them first, then asks.
  static Future<bool> needsPermissionPrompt(NotificationPreferences preferences) async =>
      supported && preferences.pushEnabled && await _storage.read(key: _permissionKey) == null;

  // Shows the system dialog (only the first time per install; afterwards it
  // just reports the current answer). Returns whether reminders can be shown.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final granted = await _requestPermission();
    await _storage.write(key: _permissionKey, value: '$granted');
    return granted;
  }

  // Saved on the server (it's the account's choice, for every phone) and
  // applied here. Turning reminders on asks the OS first; if it refuses, push
  // stays off rather than claiming reminders that can't be shown. Returns the
  // saved preferences; throws like any ApiClient call.
  static Future<NotificationPreferences> save(NotificationPreferences wanted) async {
    var preferences = wanted;
    if (wanted.pushEnabled && supported && !await requestPermission()) {
      preferences = wanted.copyWith(pushEnabled: false);
    }
    final saved = await ApiClient.updateNotificationPreferences(preferences);
    await apply(saved);
    return saved;
  }

  // Caches the preferences and reschedules (or clears) this phone's reminders.
  static Future<void> apply(NotificationPreferences preferences) async {
    await _cache(preferences);
    if (!supported) return;
    if (preferences.pushEnabled) {
      await sync();
    } else {
      await cancelAll();
    }
  }

  static Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  static Future<bool> _canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  // Re-checked every time the app comes back to the foreground, so the banner
  // goes away once the user fixed it in the system settings (and comes back if
  // they turn notifications off there).
  static Future<ReminderHealth> health() async {
    if (!supported) return ReminderHealth.ok;
    try {
      await init();
      final preferences = await cachedPreferences();
      if (preferences != null && !preferences.pushEnabled) return ReminderHealth.off;
      if (Platform.isAndroid) {
        // The real, current answer — the user may have changed it in settings.
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (await android?.areNotificationsEnabled() == false) return ReminderHealth.blocked;
      } else if (await _storage.read(key: _permissionKey) == 'false') {
        return ReminderHealth.blocked;
      }
      // Android 14+ denies exact alarms by default; without them a reminder
      // can arrive several minutes late.
      if (!await _canScheduleExact()) return ReminderHealth.inexact;
    } catch (_) {
      return ReminderHealth.ok;
    }
    return ReminderHealth.ok;
  }

  static Future<void> requestExactAlarms() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    await sync();
  }

  static Future<void>? _syncInFlight;
  static bool _syncAgain = false;

  // Coalesces bursts (several tabs reporting changes at once) into at most one
  // running sync plus one queued re-run with the latest data.
  static Future<void> sync() {
    if (_syncInFlight != null) {
      _syncAgain = true;
      return _syncInFlight!;
    }
    return _syncInFlight = () async {
      try {
        do {
          _syncAgain = false;
          try {
            await _doSync();
          } catch (_) {
            // A plugin/permission error (e.g. exact alarms revoked meanwhile)
            // must not surface as an unhandled error; the next sync retries.
          }
        } while (_syncAgain);
      } finally {
        _syncInFlight = null;
      }
    }();
  }

  // Real doses plus projections for one profile; projections are skipped (not
  // fatal) if the treatments can't be loaded.
  static Future<List<ScheduledDose>> _dosesWithProjections(DateTime now, {String? profileId}) async {
    final doses = await ApiClient.getScheduledDoses(profileId: profileId);
    try {
      final treatments = await ApiClient.getTreatments(profileId: profileId);
      return [...doses, ...projectDoses(treatments, doses, now)];
    } catch (_) {
      return doses;
    }
  }

  static Future<void> _doSync() async {
    if (!supported) return;
    await init();
    final preferences = await refreshPreferences() ?? const NotificationPreferences();
    if (!preferences.pushEnabled) {
      await _plugin.cancelAllPendingNotifications();
      return;
    }

    final now = DateTime.now();
    final List<ScheduledDose> own;
    try {
      own = await _dosesWithProjections(now);
    } catch (_) {
      // Offline or logged out: keep whatever was scheduled last time.
      return;
    }

    // Caregiver mode: the people this user looks after get reminders too, if
    // the account asked for them. One they can't see anymore (e.g. they
    // revoked access) is simply skipped.
    final dependents = <DependentDoses>[];
    if (preferences.includeDependents) {
      List<ProfileSummary> profiles;
      try {
        profiles = await ApiClient.getDependents();
      } catch (_) {
        profiles = const [];
      }
      for (final profile in profiles) {
        try {
          dependents.add((profile: profile, doses: await _dosesWithProjections(now, profileId: profile.id)));
        } catch (_) {}
      }
    }

    final toSchedule = buildReminders(preferences, own, dependents, now);

    final mode = await _canScheduleExact()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _plugin.cancelAllPendingNotifications();
    for (final reminder in toSchedule) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        // scheduledAt is a local wall-clock time; UTC is just the carrier for
        // that exact instant.
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
        notificationDetails: _detailsFor(reminder),
        androidScheduleMode: mode,
        title: reminder.title,
        body: reminder.body,
        payload: reminder.payload.encode(),
      );
    }
  }

  // On logout: no reminders and no preferences left from this account (the
  // next one fetches its own). Never throws — the logout path must complete.
  static Future<void> forgetAccount() async {
    await cancelAll();
    try {
      await _storage.delete(key: _preferencesKey);
    } catch (_) {}
  }

  // Never throws: it runs on the logout path, which must always complete.
  static Future<void> cancelAll() async {
    if (!supported) return;
    try {
      await init();
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {}
  }
}
