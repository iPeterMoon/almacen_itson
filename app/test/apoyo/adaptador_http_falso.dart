import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

// Adaptador HTTP falso para probar repositorios sin salir a la red: guarda la
// última petición y responde el estado y el cuerpo JSON indicados. Con
// [falloDeRed] simula que el servidor no responde.
class AdaptadorHttpFalso implements HttpClientAdapter {
  AdaptadorHttpFalso({this.estado = 200, this.cuerpo, this.falloDeRed = false});

  int estado;
  Object? cuerpo;
  bool falloDeRed;
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
