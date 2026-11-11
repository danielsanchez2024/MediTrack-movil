// How the account wants to be reminded of doses (GET/PUT
// /users/me/notification-preferences). Email and SMS are sent by the backend;
// push is this app's own local notifications — the backend only stores that
// choice, so every phone of the account follows it.
enum ReminderTiming {
  before('BEFORE', '10 min antes'),
  atTime('AT_TIME', 'A la hora'),
  both('BOTH', 'Ambos');

  const ReminderTiming(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get includesBefore => this != atTime;
  bool get includesAtTime => this != before;

  static ReminderTiming fromApi(String? value) =>
      values.firstWhere((t) => t.apiValue == value, orElse: () => both);
}

class NotificationPreferences {
  const NotificationPreferences({
    this.emailEnabled = true,
    this.emailTiming = ReminderTiming.both,
    this.smsEnabled = false,
    this.smsTiming = ReminderTiming.atTime,
    this.phoneNumber,
    this.pushEnabled = true,
    this.pushTiming = ReminderTiming.both,
    this.includeDependents = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) => NotificationPreferences(
        emailEnabled: json['emailEnabled'] as bool? ?? true,
        emailTiming: ReminderTiming.fromApi(json['emailTiming'] as String?),
        smsEnabled: json['smsEnabled'] as bool? ?? false,
        smsTiming: ReminderTiming.fromApi(json['smsTiming'] as String?),
        phoneNumber: json['phoneNumber'] as String?,
        pushEnabled: json['pushEnabled'] as bool? ?? true,
        pushTiming: ReminderTiming.fromApi(json['pushTiming'] as String?),
        includeDependents: json['includeDependents'] as bool? ?? true,
      );

  final bool emailEnabled;
  final ReminderTiming emailTiming;
  final bool smsEnabled;
  final ReminderTiming smsTiming;
  final String? phoneNumber;
  final bool pushEnabled;
  final ReminderTiming pushTiming;
  final bool includeDependents;

  Map<String, dynamic> toJson() => {
        'emailEnabled': emailEnabled,
        'emailTiming': emailTiming.apiValue,
        'smsEnabled': smsEnabled,
        'smsTiming': smsTiming.apiValue,
        'phoneNumber': phoneNumber,
        'pushEnabled': pushEnabled,
        'pushTiming': pushTiming.apiValue,
        'includeDependents': includeDependents,
      };

  NotificationPreferences copyWith({
    bool? emailEnabled,
    ReminderTiming? emailTiming,
    bool? smsEnabled,
    ReminderTiming? smsTiming,
    String? phoneNumber,
    bool? pushEnabled,
    ReminderTiming? pushTiming,
    bool? includeDependents,
  }) =>
      NotificationPreferences(
        emailEnabled: emailEnabled ?? this.emailEnabled,
        emailTiming: emailTiming ?? this.emailTiming,
        smsEnabled: smsEnabled ?? this.smsEnabled,
        smsTiming: smsTiming ?? this.smsTiming,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        pushTiming: pushTiming ?? this.pushTiming,
        includeDependents: includeDependents ?? this.includeDependents,
      );
}
