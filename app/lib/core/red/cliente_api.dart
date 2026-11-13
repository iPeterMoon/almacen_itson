import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/configuracion_api.dart';

// Devuelve el token de sesión actual, o null si no hay sesión.
typedef ObtenerToken = Future<String?> Function();

// Se llama cuando el servidor rechaza el token (401): la sesión ya no sirve.
typedef AlPerderSesion = void Function();

// Cliente HTTP único de la app. Agrega "Authorization: Bearer <token>" a cada
// petición cuando hay sesión. La app solo habla con el servidor NestJS, nunca
// con Supabase. [adaptador] solo se pasa en las pruebas, para no salir a la red.
Dio crearClienteApi({
  required String urlBase,
  required ObtenerToken obtenerToken,
  AlPerderSesion? alPerderSesion,
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
      onError: (error, handler) {
        if (error.response?.statusCode == 401) alPerderSesion?.call();
        handler.next(error);
      },
    ),
  );
  return dio;
}

// Token por defecto: sin sesión no se manda la cabecera. arranque.dart lo
// reemplaza por el token de la sesión guardada (y lo renueva al vencer).
final proveedorObtenerToken = Provider<ObtenerToken>((ref) => () async => null);

// La app sobrescribe este proveedor para cerrar la sesión cuando el API
// responde 401. En pruebas o sin sesión no hace nada.
final proveedorAlPerderSesion = Provider<AlPerderSesion>((ref) => () {});

final proveedorClienteApi = Provider<Dio>((ref) {
  final dio = crearClienteApi(
    urlBase: ref.watch(proveedorUrlApi),
    obtenerToken: ref.watch(proveedorObtenerToken),
    alPerderSesion: () => ref.read(proveedorAlPerderSesion)(),
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
