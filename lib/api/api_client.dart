import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/adherence_summary.dart';
import '../models/caregiver.dart';
import '../models/consent_status.dart';
import '../models/emergency_card.dart';
import '../models/notification_preferences.dart';
import '../models/scanned_medication.dart';
import '../models/scheduled_dose.dart';
import '../models/treatment.dart';
import '../models/user_profile.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart' show isoDate, timeZoneParam;
import 'token_storage.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

// The access token was missing, expired, or revoked. Distinct from ApiException
// so the UI can send the user back to the login screen instead of just showing
// an inline error.
class UnauthenticatedException implements Exception {}

class LoginResult {
  LoginResult({
    required this.token,
    required this.refreshToken,
    required this.userId,
    required this.name,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
      );

  final String token;
  final String refreshToken;
  final String userId;
  final String name;
}

class ApiClient {
  ApiClient._();

  // Override at build time for anything other than the defaults below, e.g. a
  // physical device on the LAN:
  //   flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api/v1
  // Plain HTTP to a LAN host only works in debug/profile builds (their
  // network_security_config allows cleartext to any host); a release build only
  // allows it to 10.0.2.2/localhost, so point a release at an https:// URL.
  static const _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  // The backend sits behind the nginx reverse proxy from docker-compose,
  // which serves both the API and the web frontend on port 80.
  // - Web preview: the browser talks straight to that host.
  // - Android emulator: 10.0.2.2 is the emulator's alias for the host
  //   machine's localhost.
  static String get _baseUrl {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    if (kIsWeb) return 'http://localhost/api/v1';
    if (Platform.isAndroid) return 'http://10.0.2.2/api/v1';
    return 'http://localhost/api/v1';
  }

  // Links the backend hands out (e.g. a privacy policy's contentUrl) are stored
  // as the host sees itself — "http://localhost/..." — which on a phone or the
  // emulator means the phone itself. Point those, and relative paths, at the
  // same server the API calls go to.
  static Uri resolveServerUrl(String url) {
    final api = Uri.parse(_baseUrl);
    final target = Uri.parse(url);
    if (!target.hasScheme) return api.resolve(url);
    const loopback = {'localhost', '127.0.0.1'};
    if (loopback.contains(target.host) && !loopback.contains(api.host)) {
      return target.replace(scheme: api.scheme, host: api.host, port: api.port);
    }
    return target;
  }

  static Future<void> _storeSession(LoginResult result) => TokenStorage.save(
        token: result.token,
        refreshToken: result.refreshToken,
        name: result.name,
        userId: result.userId,
      );

  static Future<LoginResult> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final result = LoginResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      await _storeSession(result);
      return result;
    }

    throw ApiException(_extractErrorMessage(response));
  }

  // Always creates an AUTONOMOUS profile (profileType isn't sent, so the
  // backend defaults to it) — dependent profiles are created by a caregiver and
  // claimed through an invite instead. Logs straight in afterwards.
  static Future<LoginResult> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required bool healthDataConsentAccepted,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'confirmPassword': confirmPassword,
        'healthDataConsentAccepted': healthDataConsentAccepted,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
    return login(email, password);
  }

  // The backend answers 204 whether or not the email has an account, so as not
  // to reveal which emails are registered — the UI must not claim either way.
  static Future<void> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException(_extractErrorMessage(response));
    }
  }

  // The backend also returns a fresh session here, but it's deliberately not
  // used: the reset sets tokensValidFrom with sub-second precision while JWT
  // `iat` is truncated to the second, so any token issued in that same second
  // (this one included) is rejected as "older" on its first use — the user
  // would be bounced straight back to login. Logging in again afterwards, as
  // the web does, sidesteps it.
  static Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'resetToken': resetToken,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );
    if (response.statusCode != 200) throw ApiException(_extractErrorMessage(response));
  }

  // Revokes this device's refresh token server-side, then forgets the session
  // locally either way — being offline must never stop someone from logging out.
  static Future<void> logout() async {
    final refreshToken = await TokenStorage.readRefreshToken();
    await TokenStorage.clear();
    if (refreshToken == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
    } catch (_) {
      // Best effort: the token still expires on its own.
    }
  }

  // The backend rotates refresh tokens (each one is revoked once used), so the
  // three tabs 401-ing at the same moment must share a single refresh call —
  // otherwise all but the first would present an already-revoked token and
  // log the user out.
  static Future<bool>? _refreshInFlight;

  static Future<bool> _refreshSession() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  // True with fresh tokens stored; false when the session is truly gone (the
  // refresh token expired or was revoked). A network failure is rethrown
  // instead, so being offline doesn't cost the user their session.
  static Future<bool> _doRefresh() async {
    final refreshToken = await TokenStorage.readRefreshToken();
    if (refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('$_baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode != 200) {
      await TokenStorage.clear();
      return false;
    }
    final result = LoginResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    await _storeSession(result);
    return true;
  }

  // Every authenticated call goes through here. The access token is
  // short-lived (an hour by default), so a 401 first tries a silent refresh and
  // retries the request once; only if that also fails is the user sent back to
  // the login screen.
  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    return _sendWithRefresh(() {
      final request = http.Request(method, uri)..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      return request;
    });
  }

  // Builds a fresh request per attempt (a request can only be sent once), signs it with the
  // current access token, and does the refresh-and-retry-once dance on a 401.
  static Future<http.Response> _sendWithRefresh(http.BaseRequest Function() build) async {
    Future<http.Response> attempt() async {
      final token = await TokenStorage.readToken();
      if (token == null) throw UnauthenticatedException();
      final request = build()..headers['Authorization'] = 'Bearer $token';
      return http.Response.fromStream(await request.send());
    }

    var response = await attempt();
    if (response.statusCode == 401) {
      if (!await _refreshSession()) throw UnauthenticatedException();
      response = await attempt();
      if (response.statusCode == 401) throw UnauthenticatedException();
    }
    return response;
  }

  static Future<dynamic> _sendJson(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Set<int> expected = const {200},
  }) async {
    final response = await _send(method, path, query: query, body: body);
    if (!expected.contains(response.statusCode)) {
      throw ApiException(_extractErrorMessage(response));
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  // The `?profileId=` every profile-scoped endpoint takes: a caregiver acting on
  // a dependent's data. Null means the logged-in user themselves.
  static Map<String, String>? _profileQuery(String? profileId, [Map<String, String>? extra]) {
    final query = {...?extra, 'profileId': ?profileId};
    return query.isEmpty ? null : query;
  }

  // `date` as an ISO yyyy-MM-dd string — omit it to get the backend's default
  // "±24h from now" window instead of a specific calendar day.
  static Future<List<ScheduledDose>> getScheduledDoses({String? date, String? profileId}) async {
    final json = await _sendJson(
      'GET',
      '/scheduled-doses',
      query: _profileQuery(
        profileId,
        date != null ? {'date': date, 'tz': timeZoneParam(DateTime.parse(date))} : null,
      ),
    );
    return (json as List)
        .map((item) => ScheduledDose.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<ScheduledDose> updateDoseStatus(
    String doseId,
    DoseStatus status,
    String? notes, {
    String? profileId,
  }) async {
    final json = await _sendJson('PATCH', '/scheduled-doses/$doseId', query: _profileQuery(profileId), body: {
      'status': doseStatusToJson(status),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return ScheduledDose.fromJson(json as Map<String, dynamic>);
  }

  static Future<AdherenceSummary> getAdherenceSummary({String? date, String? profileId}) async {
    // Without a date the backend means "today" — this phone's today, via tz.
    final day = date != null ? DateTime.parse(date) : DateTime.now();
    final json = await _sendJson(
      'GET',
      '/scheduled-doses/summary',
      query: _profileQuery(profileId, {'date': date ?? isoDate(day), 'tz': timeZoneParam(day)}),
    );
    return AdherenceSummary.fromJson(json as Map<String, dynamic>);
  }

  static Future<List<Treatment>> getTreatments({String? profileId}) async {
    final json = await _sendJson('GET', '/treatments', query: _profileQuery(profileId));
    return (json as List).map((e) => Treatment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Treatment>> getInactiveTreatments({String? profileId}) async {
    final json = await _sendJson('GET', '/treatments/inactive', query: _profileQuery(profileId));
    return (json as List).map((e) => Treatment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Treatment> updateTreatment(String id, Map<String, dynamic> payload, {String? profileId}) async {
    final json = await _sendJson('PATCH', '/treatments/$id', query: _profileQuery(profileId), body: payload);
    return Treatment.fromJson(json as Map<String, dynamic>);
  }

  static Future<void> deactivateTreatment(String id, {String? profileId}) async {
    await _sendJson('PATCH', '/treatments/$id/deactivate',
        query: _profileQuery(profileId), expected: const {204});
  }

  static Future<ConsentStatus> getConsentStatus() async {
    final json = await _sendJson('GET', '/users/me/consent-status');
    return ConsentStatus.fromJson(json as Map<String, dynamic>);
  }

  static Future<ConsentStatus> acceptCurrentPrivacyPolicy() async {
    final json = await _sendJson('POST', '/users/me/consent-status/accept');
    return ConsentStatus.fromJson(json as Map<String, dynamic>);
  }

  // With ids, unlike the emergency card's own allergy list — needed to edit them.
  static Future<List<EmergencyAllergy>> getAllergies({String? profileId}) async {
    final json = await _sendJson('GET', '/users/allergies', query: _profileQuery(profileId));
    return (json as List).map((e) => EmergencyAllergy.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<EmergencyAllergy> addAllergy(String description, String severity, {String? profileId}) async {
    final json = await _sendJson('POST', '/users/allergies',
        query: _profileQuery(profileId), body: {'description': description, 'severity': severity});
    return EmergencyAllergy.fromJson(json as Map<String, dynamic>);
  }

  static Future<EmergencyAllergy> updateAllergy(
    String id,
    String description,
    String severity, {
    String? profileId,
  }) async {
    final json = await _sendJson('PATCH', '/users/allergies/$id',
        query: _profileQuery(profileId), body: {'description': description, 'severity': severity});
    return EmergencyAllergy.fromJson(json as Map<String, dynamic>);
  }

  static Future<void> deleteAllergy(String id, {String? profileId}) async {
    await _sendJson('DELETE', '/users/allergies/$id', query: _profileQuery(profileId), expected: const {204});
  }

  // Both fields are replaced as given — null for both removes the contact.
  static Future<void> updateEmergencyContact({String? name, String? phone, String? profileId}) async {
    await _sendJson('PATCH', '/users/emergency-contact',
        query: _profileQuery(profileId),
        body: {'emergencyContactName': name, 'emergencyContactPhone': phone});
  }

  static Future<Uint8List> getEmergencyCardPdf({String? profileId}) async {
    final response = await _send('GET', '/emergency-card/pdf', query: _profileQuery(profileId));
    if (response.statusCode != 200) throw ApiException(_extractErrorMessage(response));
    return response.bodyBytes;
  }

  // Sends the photo to the backend, which has an AI vision model read the medications off it
  // (see PrescriptionScanService) — a single image can take from seconds to a couple of
  // minutes. Nothing is created here: the user reviews every medication first.
  static Future<List<ScannedMedication>> scanPrescription(Uint8List image, {String filename = 'formula.jpg'}) async {
    final uri = Uri.parse('$_baseUrl/prescriptions/scan');
    final response = await _sendWithRefresh(
      () => http.MultipartRequest('POST', uri)..files.add(http.MultipartFile.fromBytes('image', image, filename: filename)),
    );
    if (response.statusCode != 200) throw ApiException(_extractErrorMessage(response));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ((json['medications'] as List?) ?? const [])
        .map((e) => ScannedMedication.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Caregiver mode ---

  // Profiles this user manages, active ones only.
  static Future<List<ProfileSummary>> getDependents() async {
    final json = await _sendJson('GET', '/users/dependents');
    return (json as List).map((e) => ProfileSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  // email is optional: only for someone who may one day claim their own account.
  static Future<ProfileSummary> createDependent({required String name, String? email}) async {
    final json = await _sendJson('POST', '/users/dependents',
        body: {'name': name, 'email': ?email}, expected: const {200, 201});
    return ProfileSummary.fromJson(json as Map<String, dynamic>);
  }

  static Future<DependentInvite> inviteDependent(String dependentId) async {
    final json = await _sendJson('POST', '/users/dependents/$dependentId/invite');
    return DependentInvite.fromJson(json as Map<String, dynamic>);
  }

  static Future<void> cancelDependentInvite(String dependentId) async {
    await _sendJson('DELETE', '/users/dependents/$dependentId/invite', expected: const {204});
  }

  // A soft delete, like deleting your own account: history is kept.
  static Future<void> deleteDependent(String dependentId) async {
    await _sendJson('DELETE', '/users/dependents/$dependentId', expected: const {204});
  }

  // The dependent's side: whether their caregiver may keep seeing their data
  // now that they have their own account.
  static Future<CaregiverAccessStatus> getCaregiverAccess() async {
    final json = await _sendJson('GET', '/users/consents/caregiver-monitoring');
    return CaregiverAccessStatus.fromJson(json as Map<String, dynamic>);
  }

  static Future<void> setCaregiverAccess(bool granted) async {
    await _sendJson('PATCH', '/users/consents/caregiver-monitoring',
        body: {'granted': granted}, expected: const {200, 204});
  }

  // A dependent turning the profile their caregiver made into their own
  // account, with the invite code the caregiver gave them. Logs them in.
  static Future<LoginResult> claimAccount({
    required String claimToken,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/claim-account'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'claimToken': claimToken,
        'email': email,
        'password': password,
        'confirmPassword': confirmPassword,
      }),
    );
    if (response.statusCode != 200) throw ApiException(_extractErrorMessage(response));
    final result = LoginResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    await _storeSession(result);
    return result;
  }

  static Future<NotificationPreferences> getNotificationPreferences() async {
    final json = await _sendJson('GET', '/users/me/notification-preferences');
    return NotificationPreferences.fromJson(json as Map<String, dynamic>);
  }

  // Always the whole set (the backend replaces it).
  static Future<NotificationPreferences> updateNotificationPreferences(
      NotificationPreferences preferences) async {
    final json = await _sendJson('PUT', '/users/me/notification-preferences', body: preferences.toJson());
    return NotificationPreferences.fromJson(json as Map<String, dynamic>);
  }

  static Future<UserProfile> getMyProfile() async {
    final userId = await TokenStorage.readUserId();
    // Sessions stored before the id was kept: a refresh stores it.
    if (userId == null && await _refreshSession()) return getMyProfile();
    if (userId == null) throw UnauthenticatedException();
    final json = await _sendJson('GET', '/users/$userId');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  // Either field may be omitted to leave it unchanged.
  static Future<UserProfile> updateProfile({String? name, String? email}) async {
    final json = await _sendJson('PATCH', '/users/me', body: {
      'name': ?name,
      'email': ?email,
    });
    final profile = UserProfile.fromJson(json as Map<String, dynamic>);
    await TokenStorage.saveName(profile.name);
    return profile;
  }

  // Revokes every other session; this device gets the fresh pair back.
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    final json = await _sendJson('PATCH', '/auth/password', body: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'confirmNewPassword': confirmNewPassword,
    });
    await _storeSession(LoginResult.fromJson(json as Map<String, dynamic>));
  }

  // A soft delete on the backend (the account is deactivated, medical history
  // kept) — either way this device's session is over.
  static Future<void> deleteAccount() async {
    await _sendJson('DELETE', '/auth/account', expected: const {204});
    await TokenStorage.clear();
  }

  static Future<EmergencyCard> getEmergencyCard({String? profileId}) async {
    final json = await _sendJson('GET', '/emergency-card', query: _profileQuery(profileId));
    return EmergencyCard.fromJson(json as Map<String, dynamic>);
  }

  static Future<Treatment> createTreatment(Map<String, dynamic> payload, {String? profileId}) async {
    final json = await _sendJson('POST', '/treatments',
        query: _profileQuery(profileId), body: payload, expected: const {200, 201});
    return Treatment.fromJson(json as Map<String, dynamic>);
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final details = (body['details'] as List?)?.whereType<String>().toList() ?? const [];
      if (details.isNotEmpty) return toSpanishMessages(details);
      final message = body['message'] as String?;
      return message != null
          ? toSpanishMessage(message)
          : 'Ocurrió un error. Intenta de nuevo en un momento.';
    } catch (_) {
      return 'No se pudo conectar con el servidor (${response.statusCode})';
    }
  }
}
