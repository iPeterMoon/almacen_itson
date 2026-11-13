import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion_repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

const _respuestaSesion = {
  'accessToken': 'token-acceso',
  'refreshToken': 'token-renovacion',
  'expiraEn': 1763000000,
  'usuario': {
    'id': 'u1',
    'nombre': 'Almacén Náinari (demo)',
    'email': 'almacen.nainari@itson.mx',
    'rol': 'ALMACENISTA',
    'campusId': 1,
    'campus': 'Náinari',
  },
};

SesionRepositorioApi crearRepositorio(AdaptadorHttpFalso adaptador) => SesionRepositorioApi(
      crearClienteApi(
        urlBase: 'http://servidor/api/v1',
        obtenerToken: () async => null,
        adaptador: adaptador,
      ),
    );

void main() {
  group('SesionRepositorioApi', () {
    test('inicia sesión con POST /usuarios/sesion y lee la respuesta', () async {
      final adaptador = AdaptadorHttpFalso(cuerpo: _respuestaSesion);

      final sesion = await crearRepositorio(adaptador).iniciarSesion(
        usuario: ' almacen.nainari@itson.mx ',
        contrasena: 'demo1234',
      );

      expect(adaptador.ultimaPeticion!.method, 'POST');
      expect(adaptador.ultimaPeticion!.uri.path, '/api/v1/usuarios/sesion');
      expect(adaptador.ultimaPeticion!.data, {
        'usuario': 'almacen.nainari@itson.mx',
        'contrasena': 'demo1234',
      });
      expect(sesion.accessToken, 'token-acceso');
      expect(sesion.usuario.nombre, 'Almacén Náinari (demo)');
    });

    test('renueva la sesión con POST /usuarios/sesion/renovar', () async {
      final adaptador = AdaptadorHttpFalso(cuerpo: _respuestaSesion);

      final sesion = await crearRepositorio(adaptador).renovar('token-renovacion');

      expect(adaptador.ultimaPeticion!.uri.path, '/api/v1/usuarios/sesion/renovar');
      expect(adaptador.ultimaPeticion!.data, {'refreshToken': 'token-renovacion'});
      expect(sesion.refreshToken, 'token-renovacion');
    });

    test('un 401 sale como ErrorNegocio con el mensaje del servidor', () async {
      final adaptador = AdaptadorHttpFalso(
        estado: 401,
        cuerpo: {
          'codigo': 'CREDENCIALES_INVALIDAS',
          'mensaje': 'El usuario o la contraseña no son correctos.',
        },
      );

      await expectLater(
        crearRepositorio(adaptador).iniciarSesion(
          usuario: 'almacen.nainari@itson.mx',
          contrasena: 'mala',
        ),
        throwsA(
          isA<ErrorNegocio>()
              .having((e) => e.codigo, 'codigo', 'CREDENCIALES_INVALIDAS')
              .having((e) => e.mensaje, 'mensaje', contains('contraseña')),
        ),
      );
    });

    test('sin red sale como ErrorNegocio SIN_CONEXION', () async {
      await expectLater(
        crearRepositorio(AdaptadorHttpFalso(falloDeRed: true)).iniciarSesion(
          usuario: 'almacen.nainari@itson.mx',
          contrasena: 'demo1234',
        ),
        throwsA(
          isA<ErrorNegocio>().having(
            (e) => e.codigo,
            'codigo',
            ErrorNegocio.codigoSinConexion,
          ),
        ),
      );
    });

    test('una respuesta sin sesión sale como error inesperado', () async {
      await expectLater(
        crearRepositorio(AdaptadorHttpFalso(cuerpo: <Object>[])).iniciarSesion(
          usuario: 'almacen.nainari@itson.mx',
          contrasena: 'demo1234',
        ),
        throwsA(
          isA<ErrorNegocio>().having(
            (e) => e.codigo,
            'codigo',
            ErrorNegocio.codigoInesperado,
          ),
        ),
      );
    });
  });
}
