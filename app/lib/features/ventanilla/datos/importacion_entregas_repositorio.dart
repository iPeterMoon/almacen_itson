import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/archivos/selector_archivos.dart';
import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';

/// Fila del Excel que el servidor rechazó. La cabecera es la fila 1.
class ErrorFilaImportacion {
  const ErrorFilaImportacion({required this.fila, required this.motivo});

  final int fila;
  final String motivo;

  factory ErrorFilaImportacion.fromJson(Map<String, dynamic> json) => ErrorFilaImportacion(
        fila: (json['fila'] as num).toInt(),
        motivo: json['motivo'] as String,
      );
}

/// Respuesta de POST /boletas/importar. Es todo o nada: con [errores] no se
/// importó ninguna boleta.
class ResultadoImportacion {
  const ResultadoImportacion({required this.importadas, this.errores = const []});

  final int importadas;
  final List<ErrorFilaImportacion> errores;

  bool get exitosa => errores.isEmpty;

  factory ResultadoImportacion.fromJson(Map<String, dynamic> json) => ResultadoImportacion(
        importadas: (json['importadas'] as num?)?.toInt() ?? 0,
        errores: [
          for (final e in json['errores'] as List<dynamic>? ?? const [])
            ErrorFilaImportacion.fromJson(e as Map<String, dynamic>),
        ],
      );
}

// Único punto de la app que importa entregas anteriores (HU11).
class ImportacionEntregasRepositorio {
  const ImportacionEntregasRepositorio(this._dio);

  final Dio _dio;

  // Un archivo de 1 000 filas tarda más que las peticiones normales (15 s).
  static const _espera = Duration(minutes: 2);

  /// [alProgresar] recibe la fracción enviada del archivo, de 0 a 1.
  Future<ResultadoImportacion> importar({
    required String nombre,
    required Uint8List contenido,
    void Function(double fraccion)? alProgresar,
  }) async {
    try {
      final respuesta = await _dio.post<Map<String, dynamic>>(
        '/boletas/importar',
        data: FormData.fromMap({
          'archivo': MultipartFile.fromBytes(
            contenido,
            filename: nombre,
            contentType: DioMediaType.parse(tipoContenidoXlsx),
          ),
        }),
        options: Options(sendTimeout: _espera, receiveTimeout: _espera),
        onSendProgress: (enviado, total) {
          if (total > 0) alProgresar?.call(enviado / total);
        },
      );
      return ResultadoImportacion.fromJson(respuesta.data!);
    } on DioException catch (error) {
      // Las filas inválidas llegan como 422 { importadas: 0, errores: [...] }, sin el
      // { codigo, mensaje } del resto de la API: no son un fallo, son un resultado.
      final cuerpo = error.response?.data;
      if (error.response?.statusCode == 422 &&
          cuerpo is Map<String, dynamic> &&
          cuerpo['errores'] is List) {
        return ResultadoImportacion.fromJson(cuerpo);
      }
      // El archivo ya se envió: el servidor pudo haber terminado la importación.
      if (error.type == DioExceptionType.receiveTimeout) {
        throw const ErrorNegocio(
          'TIEMPO_AGOTADO',
          'El servidor tardó demasiado en responder. '
              'Revisa el historial antes de volver a importar el archivo.',
        );
      }
      throw ErrorNegocio.desdeDio(error);
    }
  }
}

final proveedorImportacionEntregasRepositorio = Provider<ImportacionEntregasRepositorio>(
  (ref) => ImportacionEntregasRepositorio(ref.watch(proveedorClienteApi)),
);
