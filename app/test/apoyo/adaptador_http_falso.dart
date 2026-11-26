import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

// Adaptador HTTP falso para probar repositorios sin salir a la red: guarda la
// última petición y responde el estado y el cuerpo JSON indicados. Con
// [falloDeRed] simula que el servidor no responde y con [tiempoAgotado], que
// recibió la petición pero no contestó a tiempo.
class AdaptadorHttpFalso implements HttpClientAdapter {
  AdaptadorHttpFalso({
    this.estado = 200,
    this.cuerpo,
    this.falloDeRed = false,
    this.tiempoAgotado = false,
  });

  int estado;
  Object? cuerpo;
  bool falloDeRed;
  bool tiempoAgotado;
  RequestOptions? ultimaPeticion;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ultimaPeticion = options;
    if (falloDeRed) {
      throw DioException.connectionError(requestOptions: options, reason: 'Sin red (prueba)');
    }
    if (tiempoAgotado) {
      throw DioException.receiveTimeout(
        timeout: options.receiveTimeout ?? Duration.zero,
        requestOptions: options,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
