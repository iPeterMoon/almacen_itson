import 'package:almacen_itson/core/config/configuracion_api.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/productos_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';
import 'producto_resumen_test.dart' show filaPinol;

ProductosRepository crearRepositorio(AdaptadorHttpFalso adaptador) {
  final dio = crearClienteApi(
    urlBase: 'http://servidor/api/v1',
    obtenerToken: () async => 'token-usuario',
    adaptador: adaptador,
  );
  return ProductosRepository(dio);
}

void main() {
  group('ProductosRepository.buscar', () {
    test('llama a GET /catalogo/productos con el texto y lee la página', () async {
      final adaptador = AdaptadorHttpFalso(
        cuerpo: {
          'datos': [filaPinol],
          'pagina': 1,
          'limite': 8,
        },
      );

      final resultado = await crearRepositorio(adaptador).buscar(texto: 'pinol');

      final peticion = adaptador.ultimaPeticion!;
      expect(peticion.method, 'GET');
      expect(peticion.uri.path, '/api/v1/catalogo/productos');
      expect(peticion.queryParameters, {'texto': 'pinol'});
      expect(peticion.headers['Authorization'], 'Bearer token-usuario');
      expect(resultado.datos.single.codigo, 'CD-123');
      expect(resultado.datos.single.existencia, 16.0);
      expect(resultado.datos.single.ubicaciones.first.almacen, 'Almacén 1');
      expect(resultado.limite, 8);
    });

    test('manda pagina y limite solo cuando se indican', () async {
      final adaptador = AdaptadorHttpFalso(
        cuerpo: {'datos': <Object>[], 'pagina': 2, 'limite': 20},
      );

      await crearRepositorio(adaptador).buscar(texto: 'cd-1', pagina: 2, limite: 20);

      expect(adaptador.ultimaPeticion!.queryParameters, {
        'texto': 'cd-1',
        'pagina': 2,
        'limite': 20,
      });
    });

    test('sin coincidencias devuelve una página vacía', () async {
      final adaptador = AdaptadorHttpFalso(
        cuerpo: {'datos': <Object>[], 'pagina': 1, 'limite': 8},
      );

      final resultado = await crearRepositorio(adaptador).buscar(texto: 'CD-500');

      expect(resultado.vacio, isTrue);
    });

    test('un 400 del servidor sale como ErrorNegocio con su código y mensaje', () async {
      final adaptador = AdaptadorHttpFalso(
        estado: 400,
        cuerpo: {
          'codigo': 'PETICION_INVALIDA',
          'mensaje': 'La petición tiene datos inválidos.',
          'detalles': ['texto must be longer than or equal to 2 characters'],
        },
      );

      await expectLater(
        crearRepositorio(adaptador).buscar(texto: 'a'),
        throwsA(
          isA<ErrorNegocio>()
              .having((e) => e.codigo, 'codigo', 'PETICION_INVALIDA')
              .having((e) => e.mensaje, 'mensaje', 'La petición tiene datos inválidos.')
              .having((e) => e.estadoHttp, 'estadoHttp', 400),
        ),
      );
    });

    test('un 401 sale como ErrorNegocio NO_AUTENTICADO', () async {
      final adaptador = AdaptadorHttpFalso(
        estado: 401,
        cuerpo: {'codigo': 'NO_AUTENTICADO', 'mensaje': 'Falta el token de sesión.'},
      );

      await expectLater(
        crearRepositorio(adaptador).buscar(texto: 'pinol'),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'NO_AUTENTICADO')),
      );
    });

    test('sin red sale como ErrorNegocio SIN_CONEXION', () async {
      final adaptador = AdaptadorHttpFalso(falloDeRed: true);

      await expectLater(
        crearRepositorio(adaptador).buscar(texto: 'pinol'),
        throwsA(
          isA<ErrorNegocio>()
              .having((e) => e.codigo, 'codigo', ErrorNegocio.codigoSinConexion)
              .having((e) => e.mensaje, 'mensaje', ErrorNegocio.mensajeSinConexion),
        ),
      );
    });
  });

  test('proveedorProductosRepository usa el cliente de la app', () async {
    final adaptador = AdaptadorHttpFalso(
      cuerpo: {'datos': <Object>[], 'pagina': 1, 'limite': 8},
    );
    final contenedor = ProviderContainer(
      overrides: [
        proveedorUrlApi.overrideWithValue('http://servidor/api/v1'),
        proveedorObtenerToken.overrideWithValue(() async => 'token-x'),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.read(proveedorClienteApi).httpClientAdapter = adaptador;

    await contenedor.read(proveedorProductosRepository).buscar(texto: 'pinol');

    expect(adaptador.ultimaPeticion!.uri.toString(),
        'http://servidor/api/v1/catalogo/productos?texto=pinol');
    expect(adaptador.ultimaPeticion!.headers['Authorization'], 'Bearer token-x');
    expect(contenedor.read(proveedorClienteApi), isA<Dio>());
  });
}
