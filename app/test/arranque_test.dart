import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/config/configuracion_api.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
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

void main() {
  group('proveedoresSegunEntorno', () {
    test('sin API_URL deja los datos simulados de Denise', () {
      final overrides = proveedoresSegunEntorno(urlApi: '', tokenDesarrollo: 'x', depuracion: true);
      final contenedor = contenedorCon(overrides);

      expect(overrides, isEmpty);
      expect(contenedor.read(ventanillaRepositorioProvider), isA<VentanillaRepositorioSimulado>());
    });

    test('con API_URL la búsqueda de materiales usa la API', () {
      final contenedor = contenedorCon(
        proveedoresSegunEntorno(urlApi: 'http://10.0.2.2:3000/api/v1', tokenDesarrollo: '', depuracion: true),
      );

      expect(contenedor.read(ventanillaRepositorioProvider), isA<VentanillaRepositorioApi>());
    });

    test('en depuración con API_TOKEN manda ese token', () async {
      final contenedor = contenedorCon(
        proveedoresSegunEntorno(urlApi: 'http://x', tokenDesarrollo: ' token-dev ', depuracion: true),
      );

      expect(await contenedor.read(proveedorObtenerToken)(), 'token-dev');
    });

    test('sin API_TOKEN no hay token', () async {
      final contenedor = contenedorCon(
        proveedoresSegunEntorno(urlApi: 'http://x', tokenDesarrollo: '', depuracion: true),
      );

      expect(await contenedor.read(proveedorObtenerToken)(), isNull);
    });

    test('fuera de depuración ignora API_TOKEN', () async {
      final contenedor = contenedorCon(
        proveedoresSegunEntorno(urlApi: 'http://x', tokenDesarrollo: 'token-dev', depuracion: false),
      );

      expect(await contenedor.read(proveedorObtenerToken)(), isNull);
      expect(contenedor.read(ventanillaRepositorioProvider), isA<VentanillaRepositorioApi>());
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
