import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Petición que recibió el servidor falso, para revisarla en la prueba.
class PeticionRegistrada {
  PeticionRegistrada(this.opciones);

  final RequestOptions opciones;

  String get metodo => opciones.method;
  String get ruta => opciones.uri.path;
  Map<String, dynamic> get consulta => opciones.queryParameters;
  String? get autorizacion => opciones.headers['Authorization'] as String?;

  /// Cuerpo JSON tal como lo armó la app (Dio lo guarda antes de serializarlo).
  Map<String, dynamic> get cuerpo => (opciones.data as Map).cast<String, dynamic>();

  @override
  String toString() => '$metodo $ruta';
}

/// Respuesta del servidor falso: estado HTTP y cuerpo JSON.
class RespuestaApi {
  const RespuestaApi(this.estado, [this.cuerpo]);

  const RespuestaApi.ok(Object? cuerpo) : this(200, cuerpo);
  const RespuestaApi.creado(Object? cuerpo) : this(201, cuerpo);

  /// Error con el mismo formato que FiltroErrores del servidor NestJS.
  RespuestaApi.error(int estado, String codigo, String mensaje, [Map<String, dynamic>? datos])
      : this(estado, {'codigo': codigo, 'mensaje': mensaje, 'datos': ?datos});

  final int estado;
  final Object? cuerpo;
}

typedef Manejador = RespuestaApi Function(PeticionRegistrada peticion);

/// Servidor NestJS simulado para las pruebas de integración de la app. Se conecta
/// como adaptador de Dio, así la petición pasa por el cliente real (interceptor
/// del token y manejo de 401) y solo se reemplaza la red.
///
/// Cada ruta se registra como "MÉTODO /ruta" relativa a /api/v1. Una ruta que no se
/// registró responde 404 y queda anotada en [noSimuladas], para que la prueba falle
/// con un mensaje claro en lugar de quedarse esperando.
class ServidorApiFalso implements HttpClientAdapter {
  ServidorApiFalso({this.prefijo = '/api/v1'});

  final String prefijo;
  final Map<String, Manejador> _rutas = {};
  final List<PeticionRegistrada> peticiones = [];
  final List<String> noSimuladas = [];

  void en(String metodoYRuta, Manejador manejador) => _rutas[metodoYRuta] = manejador;

  /// Peticiones a una ruta, en orden ("POST /boletas").
  List<PeticionRegistrada> a(String metodoYRuta) =>
      [for (final p in peticiones) if ('${p.metodo} ${_sinPrefijo(p.ruta)}' == metodoYRuta) p];

  String _sinPrefijo(String ruta) =>
      ruta.startsWith(prefijo) ? ruta.substring(prefijo.length) : ruta;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final peticion = PeticionRegistrada(options);
    peticiones.add(peticion);
    final clave = '${options.method} ${_sinPrefijo(options.uri.path)}';
    final manejador = _rutas[clave];
    if (manejador == null) noSimuladas.add(clave);
    final respuesta = manejador?.call(peticion) ??
        RespuestaApi.error(404, 'NO_ENCONTRADO', 'Ruta no simulada en la prueba: $clave');
    return ResponseBody.fromString(
      jsonEncode(respuesta.cuerpo),
      respuesta.estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
