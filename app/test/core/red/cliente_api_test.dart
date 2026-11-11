import 'dart:convert';
import 'dart:typed_data';

import 'package:almacen_itson/core/config/configuracion_api.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Adaptador HTTP falso: guarda la petición que recibió y responde un JSON fijo,
// sin salir a la red.
class AdaptadorFalso implements HttpClientAdapter {
  RequestOptions? ultimaPeticion;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ultimaPeticion = options;
    return ResponseBody.fromString(
      jsonEncode({'datos': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('crearClienteApi', () {
    test('agrega el token de sesión como Bearer', () async {
      final adaptador = AdaptadorFalso();
      final dio = crearClienteApi(
        urlBase: 'http://servidor/api/v1',
        obtenerToken: () async => 'token-usuario',
        adaptador: adaptador,
      );

      final respuesta = await dio.get<Map<String, dynamic>>('/catalogo/productos');

      expect(adaptador.ultimaPeticion!.headers['Authorization'], 'Bearer token-usuario');
      expect(adaptador.ultimaPeticion!.uri.toString(), 'http://servidor/api/v1/catalogo/productos');
      expect(respuesta.data, {'datos': []});
    });

    test('sin sesión no manda el encabezado Authorization', () async {
      final adaptador = AdaptadorFalso();
      final dio = crearClienteApi(
        urlBase: 'http://servidor/api/v1',
        obtenerToken: () async => null,
        adaptador: adaptador,
      );

      await dio.get<Object?>('/catalogo/productos');

      expect(adaptador.ultimaPeticion!.headers.containsKey('Authorization'), isFalse);
    });

    test('pide el token en cada petición, para usar siempre el vigente', () async {
      final adaptador = AdaptadorFalso();
      var vez = 0;
      final dio = crearClienteApi(
        urlBase: 'http://servidor/api/v1',
        obtenerToken: () async => 'token-${++vez}',
        adaptador: adaptador,
      );

      await dio.get<Object?>('/a');
      await dio.get<Object?>('/b');

      expect(adaptador.ultimaPeticion!.headers['Authorization'], 'Bearer token-2');
    });
  });

  group('proveedorClienteApi', () {
    test('usa la URL y el token de sus proveedores', () async {
      final adaptador = AdaptadorFalso();
      final contenedor = ProviderContainer(
        overrides: [
          proveedorUrlApi.overrideWithValue('http://servidor/api/v1'),
          proveedorObtenerToken.overrideWithValue(() async => 'token-x'),
        ],
      );
      addTearDown(contenedor.dispose);

      final dio = contenedor.read(proveedorClienteApi)..httpClientAdapter = adaptador;
      await dio.get<Object?>('/catalogo/productos');

      expect(adaptador.ultimaPeticion!.uri.toString(), 'http://servidor/api/v1/catalogo/productos');
      expect(adaptador.ultimaPeticion!.headers['Authorization'], 'Bearer token-x');
    });
  });

  group('leerUrlApi', () {
    test('quita la diagonal final', () {
      expect(leerUrlApi('http://10.0.2.2:3000/api/v1/'), 'http://10.0.2.2:3000/api/v1');
    });

    test('falla con un mensaje claro si falta API_URL', () {
      expect(
        () => leerUrlApi(''),
        throwsA(isA<StateError>().having((e) => e.message, 'mensaje', contains('API_URL'))),
      );
    });
  });
}
