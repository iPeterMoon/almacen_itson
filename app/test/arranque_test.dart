import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/config/configuracion_api.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/autenticacion/datos/almacen_sesion.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

ProviderContainer contenedorCon(List<Override> overrides) {
  final contenedor = ProviderContainer(overrides: [
    proveedorUrlApi.overrideWithValue('http://servidor/api/v1'),
    ...overrides,
  ]);
  addTearDown(contenedor.dispose);
  return contenedor;
}

Sesion sesionVigente() => Sesion(
      accessToken: 'token-acceso',
      refreshToken: 'token-renovacion',
      expiraEn: DateTime.now().add(const Duration(hours: 1)),
      usuario: const UsuarioSesion(
        id: 'u1',
        nombre: 'Almacén Náinari (demo)',
        email: 'almacen.nainari@itson.mx',
        rol: 'ALMACENISTA',
        campusId: 1,
        campus: 'Náinari',
      ),
    );

void main() {
  group('proveedoresSegunEntorno', () {
    test('sin API_URL mantiene la ventanilla simulada', () {
      final contenedor = contenedorCon(proveedoresSegunEntorno(urlApi: ''));

      expect(contenedor.read(ventanillaRepositorioProvider), isA<VentanillaRepositorioSimulado>());
    });

    test('con API_URL la búsqueda de materiales usa la API', () {
      final contenedor = contenedorCon(
        proveedoresSegunEntorno(urlApi: 'http://10.0.2.2:3000/api/v1'),
      );

      expect(contenedor.read(ventanillaRepositorioProvider), isA<VentanillaRepositorioApi>());
    });

    test('el cliente HTTP usa el token de la sesión guardada', () async {
      final contenedor = contenedorCon([
        proveedorAlmacenSesion.overrideWithValue(AlmacenSesionMemoria(sesionVigente())),
        ...proveedoresSegunEntorno(urlApi: 'http://x'),
      ]);

      expect(await contenedor.read(proveedorObtenerToken)(), 'token-acceso');
    });

    test('sin sesión guardada no hay token', () async {
      final contenedor = contenedorCon([
        proveedorAlmacenSesion.overrideWithValue(AlmacenSesionMemoria()),
        ...proveedoresSegunEntorno(urlApi: 'http://x'),
      ]);

      expect(await contenedor.read(proveedorObtenerToken)(), isNull);
    });
  });

  group('reintentoProveedores', () {
    test('no reintenta un error que mandó el servidor', () {
      const error = ErrorNegocio('NO_AUTENTICADO', 'Falta el token de sesión.', estadoHttp: 401);

      expect(reintentoProveedores(0, error), isNull);
    });

    test('sin conexión reintenta 3 veces con espera creciente', () {
      const error = ErrorNegocio(ErrorNegocio.codigoSinConexion, ErrorNegocio.mensajeSinConexion);

      expect(reintentoProveedores(0, error), const Duration(milliseconds: 500));
      expect(reintentoProveedores(1, error), const Duration(seconds: 1));
      expect(reintentoProveedores(2, error), const Duration(seconds: 2));
      expect(reintentoProveedores(3, error), isNull);
    });

    test('otros fallos también reintentan hasta 3 veces', () {
      expect(reintentoProveedores(0, StateError('x')), isNotNull);
      expect(reintentoProveedores(3, StateError('x')), isNull);
    });
  });
}
