import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException errorConRespuesta(int estado, Object? cuerpo) {
  final peticion = RequestOptions(path: '/catalogo/productos');
  return DioException(
    requestOptions: peticion,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(requestOptions: peticion, statusCode: estado, data: cuerpo),
  );
}

void main() {
  group('ErrorNegocio.fromJson', () {
    test('lee el código y el mensaje del servidor', () {
      final error = ErrorNegocio.fromJson(
        {'codigo': 'STOCK_INSUFICIENTE', 'mensaje': 'Solo hay 4 piezas.'},
        estadoHttp: 409,
      );

      expect(error.codigo, 'STOCK_INSUFICIENTE');
      expect(error.mensaje, 'Solo hay 4 piezas.');
      expect(error.estadoHttp, 409);
    });

    test('un cuerpo sin código o mensaje se trata como error inesperado', () {
      final error = ErrorNegocio.fromJson({'message': 'Internal'});

      expect(error.codigo, ErrorNegocio.codigoInesperado);
      expect(error.mensaje, ErrorNegocio.mensajeInesperado);
    });
  });

  group('ErrorNegocio.desdeDio', () {
    test('convierte la respuesta { codigo, mensaje } con su estado HTTP', () {
      final error = ErrorNegocio.desdeDio(
        errorConRespuesta(400, {
          'codigo': 'PETICION_INVALIDA',
          'mensaje': 'La petición tiene datos inválidos.',
          'detalles': ['texto must be longer than or equal to 2 characters'],
        }),
      );

      expect(error.codigo, 'PETICION_INVALIDA');
      expect(error.mensaje, 'La petición tiene datos inválidos.');
      expect(error.estadoHttp, 400);
    });

    test('una sesión vencida conserva el código del servidor', () {
      final error = ErrorNegocio.desdeDio(
        errorConRespuesta(401, {'codigo': 'NO_AUTENTICADO', 'mensaje': 'Falta el token de sesión.'}),
      );

      expect(error.codigo, 'NO_AUTENTICADO');
      expect(error.estadoHttp, 401);
    });

    test('una respuesta que no es JSON se trata como error inesperado', () {
      final error = ErrorNegocio.desdeDio(errorConRespuesta(502, '<html>Bad Gateway</html>'));

      expect(error.codigo, ErrorNegocio.codigoInesperado);
      expect(error.estadoHttp, 502);
    });

    test('sin respuesta por falta de red indica que no hay conexión', () {
      for (final tipo in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final error = ErrorNegocio.desdeDio(
          DioException(requestOptions: RequestOptions(path: '/x'), type: tipo),
        );

        expect(error.codigo, ErrorNegocio.codigoSinConexion, reason: '$tipo');
        expect(error.mensaje, ErrorNegocio.mensajeSinConexion);
      }
    });

    test('devuelve el mismo ErrorNegocio si ya venía dentro del DioException', () {
      const original = ErrorNegocio('SIN_PERMISO', 'No puedes consultar ese campus.');

      final error = ErrorNegocio.desdeDio(
        DioException(requestOptions: RequestOptions(path: '/x'), error: original),
      );

      expect(error, same(original));
    });
  });
}
