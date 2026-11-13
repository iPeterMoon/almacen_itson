// Sesión que devuelve POST /usuarios/sesion. La app guarda el par de tokens y
// el perfil para saber a qué campus pertenece el usuario y qué rol tiene.
class UsuarioSesion {
  const UsuarioSesion({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.campusId,
    required this.campus,
  });

  final String id;
  final String nombre;
  final String email;
  final String rol;
  final int campusId;
  final String campus;

  factory UsuarioSesion.fromJson(Map<String, dynamic> json) => UsuarioSesion(
        id: _textoObligatorio(json, 'id'),
        nombre: _textoObligatorio(json, 'nombre'),
        email: (json['email'] as String?) ?? '',
        rol: _textoObligatorio(json, 'rol'),
        campusId: _enteroObligatorio(json, 'campusId'),
        campus: (json['campus'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'email': email,
        'rol': rol,
        'campusId': campusId,
        'campus': campus,
      };

  // Texto legible para la interfaz; el valor de la API no se traduce.
  String get rolLegible => switch (rol) {
        'ALMACENISTA' => 'Almacenista',
        'SUPERVISOR' => 'Supervisor',
        'SUPERVISOR_JEFE' => 'Supervisor jefe',
        'ADMIN' => 'Administrador',
        _ => rol,
      };
}

class Sesion {
  const Sesion({
    required this.accessToken,
    required this.refreshToken,
    required this.expiraEn,
    required this.usuario,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiraEn;
  final UsuarioSesion usuario;

  factory Sesion.fromJson(Map<String, dynamic> json) {
    final usuario = json['usuario'];
    if (usuario is! Map) {
      throw const FormatException('La respuesta de sesión no incluye el usuario.');
    }
    return Sesion(
      accessToken: _textoObligatorio(json, 'accessToken'),
      refreshToken: _textoObligatorio(json, 'refreshToken'),
      expiraEn: _fechaObligatoria(json['expiraEn']),
      usuario: UsuarioSesion.fromJson(usuario.cast<String, dynamic>()),
    );
  }

  // Se guarda en flutter_secure_storage como JSON. La fecha va en ISO 8601.
  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiraEn': expiraEn.toUtc().toIso8601String(),
        'usuario': usuario.toJson(),
      };

  // Se renueva un minuto antes para no mandar un token que vence en el camino.
  bool get estaVigente =>
      DateTime.now().isBefore(expiraEn.subtract(const Duration(minutes: 1)));
}

String _textoObligatorio(Map<String, dynamic> json, String clave) {
  final valor = json[clave];
  if (valor is String && valor.trim().isNotEmpty) return valor;
  throw FormatException('Falta "$clave" en la respuesta de sesión.');
}

int _enteroObligatorio(Map<String, dynamic> json, String clave) {
  final valor = json[clave];
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  throw FormatException('Falta "$clave" en la respuesta de sesión.');
}

DateTime _fechaObligatoria(Object? valor) {
  if (valor is int) {
    return DateTime.fromMillisecondsSinceEpoch(valor * 1000, isUtc: true);
  }
  if (valor is String) {
    final fecha = DateTime.tryParse(valor);
    if (fecha != null) return fecha;
  }
  throw const FormatException('La respuesta de sesión no incluye una fecha de expiración válida.');
}
