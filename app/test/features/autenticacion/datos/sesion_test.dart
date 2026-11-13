import 'package:almacen_itson/features/autenticacion/datos/sesion.dart';
import 'package:flutter_test/flutter_test.dart';

const _usuario = {
  'id': 'u1',
  'nombre': 'Almacén Náinari (demo)',
  'email': 'almacen.nainari@itson.mx',
  'rol': 'ALMACENISTA',
  'campusId': 1,
  'campus': 'Náinari',
};

void main() {
  group('Sesion.fromJson', () {
    test('lee los tokens y el perfil del servidor', () {
      final sesion = Sesion.fromJson({
        'accessToken': 'token-acceso',
        'refreshToken': 'token-renovacion',
        'expiraEn': 1763000000,
        'usuario': _usuario,
      });

      expect(sesion.accessToken, 'token-acceso');
      expect(sesion.refreshToken, 'token-renovacion');
      expect(sesion.expiraEn.toUtc(), DateTime.fromMillisecondsSinceEpoch(1763000000 * 1000, isUtc: true));
      expect(sesion.usuario.nombre, 'Almacén Náinari (demo)');
      expect(sesion.usuario.rolLegible, 'Almacenista');
      expect(sesion.usuario.campus, 'Náinari');
    });

    test('acepta la fecha en ISO 8601 (formato que guarda la app)', () {
      final sesion = Sesion.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiraEn': '2030-01-01T00:00:00.000Z',
        'usuario': _usuario,
      });

      expect(sesion.expiraEn, DateTime.utc(2030));
    });

    test('falla si la respuesta no trae el usuario', () {
      expect(
        () => Sesion.fromJson({
          'accessToken': 'a',
          'refreshToken': 'r',
          'expiraEn': 1763000000,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('falla si falta un token', () {
      expect(
        () => Sesion.fromJson({
          'accessToken': 'a',
          'expiraEn': 1763000000,
          'usuario': _usuario,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson se puede volver a leer', () {
      final original = Sesion.fromJson({
        'accessToken': 'token-acceso',
        'refreshToken': 'token-renovacion',
        'expiraEn': 1763000000,
        'usuario': _usuario,
      });

      final copia = Sesion.fromJson(original.toJson());

      expect(copia.accessToken, original.accessToken);
      expect(copia.refreshToken, original.refreshToken);
      expect(copia.expiraEn.toUtc(), original.expiraEn.toUtc());
      expect(copia.usuario.toJson(), original.usuario.toJson());
    });
  });

  group('Sesion.estaVigente', () {
    test('es vigente cuando faltan más de un minuto', () {
      final sesion = Sesion(
        accessToken: 'a',
        refreshToken: 'r',
        expiraEn: DateTime.now().add(const Duration(minutes: 5)),
        usuario: const UsuarioSesion(
          id: 'u1',
          nombre: 'Ana',
          email: 'ana@itson.mx',
          rol: 'ALMACENISTA',
          campusId: 1,
          campus: 'Náinari',
        ),
      );

      expect(sesion.estaVigente, isTrue);
    });

    test('deja de ser vigente un minuto antes de expirar', () {
      final sesion = Sesion(
        accessToken: 'a',
        refreshToken: 'r',
        expiraEn: DateTime.now().add(const Duration(seconds: 30)),
        usuario: const UsuarioSesion(
          id: 'u1',
          nombre: 'Ana',
          email: 'ana@itson.mx',
          rol: 'ALMACENISTA',
          campusId: 1,
          campus: 'Náinari',
        ),
      );

      expect(sesion.estaVigente, isFalse);
    });
  });
}
