import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'core/errores/error_negocio.dart';
import 'core/red/cliente_api.dart';
import 'features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'features/ventanilla/presentacion/entrega_controlador.dart';

// Valores que se pasan al compilar con --dart-define. Nunca se escriben en el código.
const String urlApiCompilada = String.fromEnvironment('API_URL');
const String tokenDesarrolloCompilado = String.fromEnvironment('API_TOKEN');

// Qué proveedores cambian según cómo se ejecuta la app:
// - Sin API_URL: todo queda como lo dejó Denise, con datos simulados (sus pruebas
//   y el diseño funcionan sin servidor).
// - Con API_URL: la búsqueda de materiales va a la API real (AI-30).
// - TEMPORAL (hasta que exista el inicio de sesión): con API_TOKEN y solo en modo
//   depuración, ese token se manda en cada petición. En una versión de
//   producción (release) se ignora aunque se haya pasado.
List<Override> proveedoresSegunEntorno({
  String urlApi = urlApiCompilada,
  String tokenDesarrollo = tokenDesarrolloCompilado,
  bool depuracion = kDebugMode,
}) {
  if (urlApi.trim().isEmpty) return const [];
  final token = tokenDesarrollo.trim();
  return [
    ventanillaRepositorioProvider.overrideWith((ref) => ref.watch(ventanillaRepositorioApiProvider)),
    if (depuracion && token.isNotEmpty) proveedorObtenerToken.overrideWithValue(() async => token),
  ];
}

// Reintentos automáticos de los proveedores (Riverpod 3 reintenta por defecto).
// Un error que mandó el servidor (sesión vencida, datos inválidos, permiso) no se
// arregla reintentando, así que se muestra de inmediato. Sin conexión u otros
// fallos se reintenta hasta 3 veces (0.5 s, 1 s y 2 s).
Duration? reintentoProveedores(int intento, Object error) {
  if (error is ErrorNegocio && error.codigo != ErrorNegocio.codigoSinConexion) return null;
  if (intento >= 3) return null;
  return Duration(milliseconds: 500 * (1 << intento));
}
