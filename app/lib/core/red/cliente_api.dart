import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/configuracion_api.dart';

// Devuelve el token de sesión actual, o null si no hay sesión.
typedef ObtenerToken = Future<String?> Function();

// Cliente HTTP único de la app. Agrega "Authorization: Bearer <token>" a cada
// petición cuando hay sesión. La app solo habla con el servidor NestJS, nunca
// con Supabase. [adaptador] solo se pasa en las pruebas, para no salir a la red.
Dio crearClienteApi({
  required String urlBase,
  required ObtenerToken obtenerToken,
  HttpClientAdapter? adaptador,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: urlBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );
  if (adaptador != null) dio.httpClientAdapter = adaptador;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (opciones, handler) async {
        final token = await obtenerToken();
        if (token != null && token.isNotEmpty) {
          opciones.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(opciones);
      },
    ),
  );
  return dio;
}

// Supuesto: todavía no existe el inicio de sesión. Mientras tanto no hay token y
// el servidor responde 401. La funcionalidad de autenticación sobrescribirá este
// proveedor con uno que lea el token guardado (y lo renueve al vencer).
final proveedorObtenerToken = Provider<ObtenerToken>((ref) => () async => null);

final proveedorClienteApi = Provider<Dio>((ref) {
  final dio = crearClienteApi(
    urlBase: ref.watch(proveedorUrlApi),
    obtenerToken: ref.watch(proveedorObtenerToken),
  );
  ref.onDispose(dio.close);
  return dio;
});

// Cliente para las rutas públicas (iniciar/renovar sesión): no manda el token
// de una sesión anterior ni depende de que exista una.
final proveedorClienteApiPublico = Provider<Dio>((ref) {
  final dio = crearClienteApi(
    urlBase: ref.watch(proveedorUrlApi),
    obtenerToken: () async => null,
  );
  ref.onDispose(dio.close);
  return dio;
});
