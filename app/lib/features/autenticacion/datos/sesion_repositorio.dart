import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import 'sesion.dart';

abstract interface class SesionRepositorio {
  Future<Sesion> iniciarSesion({required String usuario, required String contrasena});
  Future<Sesion> renovar(String refreshToken);
}

class SesionRepositorioApi implements SesionRepositorio {
  SesionRepositorioApi(this._dio);

  final Dio _dio;

  @override
  Future<Sesion> iniciarSesion({
    required String usuario,
    required String contrasena,
  }) async {
    final respuesta = await _pedir(
      '/usuarios/sesion',
      {'usuario': usuario.trim(), 'contrasena': contrasena},
    );
    return respuesta;
  }

  @override
  Future<Sesion> renovar(String refreshToken) {
    return _pedir('/usuarios/sesion/renovar', {'refreshToken': refreshToken});
  }

  Future<Sesion> _pedir(String ruta, Map<String, dynamic> cuerpo) async {
    try {
      final respuesta = await _dio.post<Object?>(ruta, data: cuerpo);
      final datos = respuesta.data;
      if (datos is! Map) {
        throw const FormatException('El servidor no devolvió una sesión.');
      }
      return Sesion.fromJson(datos.cast<String, dynamic>());
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    } on FormatException {
      throw const ErrorNegocio(
        ErrorNegocio.codigoInesperado,
        'El servidor devolvió una respuesta inesperada. Intenta de nuevo.',
      );
    }
  }
}

final proveedorSesionRepositorio = Provider<SesionRepositorio>(
  (ref) => SesionRepositorioApi(ref.watch(proveedorClienteApiPublico)),
);
