// The backend's error messages are in English (see meditrack-backend's DTOs and
// exceptions). Same mapping as the web's src/lib/errorMessages.ts, plus the
// treatment-form validation messages the mobile forms can hit; anything
// unrecognized falls back to a generic message rather than leaking raw backend text.
const _knownMessages = {
  'Invalid email or password': 'Email o contraseña incorrectos.',
  'A user with this email already exists': 'Ya existe una cuenta con este correo electrónico.',
  'Name is required': 'El nombre es obligatorio.',
  'Email is required': 'El correo electrónico es obligatorio.',
  'Email format is invalid': 'El formato del correo electrónico no es válido.',
  'Password is required': 'La contraseña es obligatoria.',
  'Password must be at least 8 characters long': 'La contraseña debe tener al menos 8 caracteres.',
  'Password confirmation is required': 'Debes confirmar la contraseña.',
  'Password and confirmation do not match': 'Las contraseñas no coinciden.',
  'You must accept the health data processing consent to register':
      'Debes aceptar el tratamiento de datos de salud para registrarte.',
  'Invalid or expired password reset link': 'Este enlace ya no es válido o expiró. Solicita uno nuevo.',
  'Reset token is required': 'Este enlace no es válido. Solicita uno nuevo.',
  'An active treatment for this medication already exists. Update it instead of creating a new one.':
      'Ya existe un tratamiento activo con este medicamento. Edítalo en vez de crear uno nuevo.',
  'A dose scheduled in the future cannot already be marked as taken':
      'Una dosis programada en el futuro no puede estar marcada como ya tomada.',
  'The first dose date cannot be in the past unless it was already taken':
      'La fecha de la primera dosis no puede estar en el pasado, a menos que marques que ya se tomó.',
  'Total quantity must be enough to cover at least one dose':
      'La cantidad total debe alcanzar al menos para una toma.',
  'Current password is incorrect': 'La contraseña actual no es correcta.',
  'Current password is required': 'Ingresa tu contraseña actual.',
  'Name must be at most 150 characters': 'El nombre puede tener como máximo 150 caracteres.',
  'This person has not granted you access to their data.':
      'Esta persona ya tiene su propia cuenta y no te ha dado acceso a sus datos.',
  'Invalid or expired invite code': 'Este código de invitación no es válido o expiró.',
  'Claim token is required': 'Debes ingresar el código de invitación.',
  'This profile has already been claimed':
      'Esta persona ya reclamó su propia cuenta, ya no necesita una invitación.',
  'Could not read the prescription image. Please try again or enter the treatment manually.':
      'No pudimos leer la fórmula. Intenta con otra foto o ingresa el medicamento manualmente.',
  'Description is required': 'La descripción es obligatoria.',
  'A phone number is required to receive SMS reminders':
      'Para recibir avisos por SMS escribe tu número de teléfono.',
  'Phone number format is invalid': 'El número de teléfono no es válido.',
  'Phone number must be at most 30 characters': 'El número de teléfono es demasiado largo.',
  'Medication name is required': 'El nombre del medicamento es obligatorio.',
  'Dosage is required': 'La dosis es obligatoria.',
  'Frequency value is required': 'La frecuencia es obligatoria.',
  'Frequency must be a positive number': 'La frecuencia debe ser un número mayor que 0.',
  'Total quantity must be a positive number': 'La cantidad suministrada debe ser mayor que 0.',
  'Quantity per dose must be a positive number': 'La cantidad por toma debe ser mayor que 0.',
};

// Some backend messages embed a dynamic value (a timestamp) and can't be
// matched exactly — matched by prefix instead, in the order given.
const _knownMessagePrefixes = [
  (
    'You must record doses in order',
    'Hay una dosis anterior de este medicamento sin resolver. Regístrala primero y luego esta se habilitará.',
  ),
  ('Profile not found', 'Este perfil ya no existe o no tienes acceso a él.'),
  ('This dose was recorded more than', 'Ya pasó el tiempo permitido para corregir esta toma.'),
  (
    "This dose can't be recorded yet",
    'Todavía no es hora de registrar esta toma — se habilita 10 minutos antes.',
  ),
];

String toSpanishMessage(String message) {
  final known = _knownMessages[message];
  if (known != null) return known;
  for (final (prefix, translation) in _knownMessagePrefixes) {
    if (message.startsWith(prefix)) return translation;
  }
  return 'Ocurrió un error. Intenta de nuevo en un momento.';
}

// Validation errors come back as `details` alongside a generic top-level
// message — translate each one and join, dropping repeats.
String toSpanishMessages(List<String> details) =>
    details.map(toSpanishMessage).toSet().join(' ');
