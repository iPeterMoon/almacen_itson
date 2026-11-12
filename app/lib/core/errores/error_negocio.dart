import 'package:dio/dio.dart';

// Error que la pantalla puede mostrar tal cual. El servidor ya convierte el
// "CODIGO: mensaje" de las funciones de la base en el cuerpo
// { "codigo": "...", "mensaje": "...", "datos": {...} }; aquí se lee ese cuerpo.
// Las pantallas muestran [mensaje] y pueden reaccionar según [codigo].
// SUPUESTO: el campo opcional "datos" trae detalles del error (por ejemplo, el
// stock disponible en STOCK_INSUFICIENTE); si no viene, queda vacío.
class ErrorNegocio implements Exception {
  const ErrorNegocio(this.codigo, this.mensaje, {this.estadoHttp, this.datos = const {}});

  // Códigos que genera la app cuando no hay respuesta del servidor.
  static const codigoSinConexion = 'SIN_CONEXION';
  static const codigoInesperado = 'ERROR_INESPERADO';

  static const mensajeSinConexion =
      'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
  static const mensajeInesperado = 'Ocurrió un error inesperado. Intenta de nuevo.';

  final String codigo;
  final String mensaje;
  final int? estadoHttp;
  final Map<String, dynamic> datos;

  // Lee { codigo, mensaje, datos }. Si el cuerpo no trae código y mensaje, se trata
  // como error inesperado en lugar de mostrar texto técnico al usuario.
  factory ErrorNegocio.fromJson(Map<String, dynamic> json, {int? estadoHttp}) {
    final codigo = json['codigo'];
    final mensaje = json['mensaje'];
    if (codigo is String && codigo.isNotEmpty && mensaje is String && mensaje.isNotEmpty) {
      return ErrorNegocio(
        codigo,
        mensaje,
        estadoHttp: estadoHttp,
        datos: (json['datos'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    }
    return ErrorNegocio(codigoInesperado, mensajeInesperado, estadoHttp: estadoHttp);
  }

  // Convierte cualquier fallo de dio en un ErrorNegocio. Los repositorios lo usan así:
  //   try { ... } on DioException catch (e) { throw ErrorNegocio.desdeDio(e); }
  factory ErrorNegocio.desdeDio(DioException error) {
    final original = error.error;
    if (original is ErrorNegocio) return original;

    final respuesta = error.response;
    if (respuesta != null) {
      final cuerpo = respuesta.data;
      if (cuerpo is Map<String, dynamic>) {
        return ErrorNegocio.fromJson(cuerpo, estadoHttp: respuesta.statusCode);
      }
      return ErrorNegocio(codigoInesperado, mensajeInesperado, estadoHttp: respuesta.statusCode);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ErrorNegocio(codigoSinConexion, mensajeSinConexion);
      default:
        return const ErrorNegocio(codigoInesperado, mensajeInesperado);
    }
  }

  @override
  String toString() => 'ErrorNegocio($codigo, $estadoHttp): $mensaje';
}
