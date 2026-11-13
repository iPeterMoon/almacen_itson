import 'package:flutter_riverpod/misc.dart' show Override;

import 'core/errores/error_negocio.dart';
import 'core/red/cliente_api.dart';
import 'features/autenticacion/presentacion/sesion_controlador.dart';
import 'features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'features/ventanilla/presentacion/entrega_controlador.dart';

// Valores que se pasan al compilar con --dart-define. Nunca se escriben en el código.
const String urlApiCompilada = String.fromEnvironment('API_URL');

// Qué proveedores cambian según cómo se ejecuta la app:
// - El cliente HTTP siempre usa el token de la sesión guardada (login real).
// - Sin API_URL la ventanilla sigue con datos simulados, para que el diseño y
//   las pruebas de la pantalla funcionen sin servidor.
// - Con API_URL la búsqueda de materiales y las entregas van a la API real.
List<Override> proveedoresSegunEntorno({String urlApi = urlApiCompilada}) {
  return [
    proveedorObtenerToken.overrideWith((ref) => ref.watch(proveedorTokenSesion)),
    if (urlApi.trim().isNotEmpty)
      ventanillaRepositorioProvider.overrideWith((ref) => ref.watch(ventanillaRepositorioApiProvider)),
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
