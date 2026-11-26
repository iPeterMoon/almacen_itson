import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import 'detalle_boleta.dart';
import 'modelos.dart';
import 'ventanilla_repositorio_api.dart' show minimoCaracteresBusqueda;

// Una fila del historial de entregas (HU11). Refleja un elemento de `datos` en
// GET /boletas/historial: { id, folio, solicitanteNombre, dependencia, entregadoEn, autorizoNombre }.
class EntregaHistorial {
  const EntregaHistorial({
    required this.id,
    required this.folio,
    required this.solicitante,
    this.dependencia,
    this.entregadoEn,
    this.supervisor,
  });

  final int id;
  final String folio; // lo genera la base; la app solo lo muestra
  final String solicitante;
  // Dependencia del trabajador, o la unidad capturada si el solicitante no está registrado.
  final String? dependencia;
  final String? entregadoEn; // ISO 8601
  // Quién autorizó la entrega (columna "Supervisor" del Figma). Null si no hubo.
  final String? supervisor;

  factory EntregaHistorial.fromJson(Map<String, dynamic> json) => EntregaHistorial(
        id: (json['id'] as num).toInt(),
        folio: json['folio'] as String,
        solicitante: json['solicitanteNombre'] as String? ?? '',
        dependencia: json['dependencia'] as String?,
        entregadoEn: json['entregadoEn'] as String?,
        supervisor: json['autorizoNombre'] as String?,
      );
}

// Excel del historial (HU11, AI-79) tal como lo genera GET /boletas/historial/exportar.
class ArchivoHistorial {
  const ArchivoHistorial({required this.nombre, required this.bytes, required this.total});

  /// Filas máximas que trae el archivo (LIMITE_EXPORTACION_BOLETAS en el servidor).
  static const maximoFilas = 1000;

  /// Nombre sugerido por el servidor, por ejemplo "historial-entregas-2026-11-25.xlsx".
  final String nombre;
  final Uint8List bytes;

  /// Boletas que cumplen el filtro (encabezado X-Total-Resultados); puede ser mayor
  /// que las filas del archivo.
  final int total;

  /// true si el archivo se cortó en [maximoFilas] y no trae todas las boletas.
  bool get recortado => total > maximoFilas;
}

/// Nombre del archivo en "Content-Disposition: attachment; filename=...". Si no
/// viene, se usa uno genérico.
String nombreDeArchivo(String? contentDisposition) {
  final nombre = RegExp(r'filename="?([^";]+)"?').firstMatch(contentDisposition ?? '')?.group(1);
  return (nombre == null || nombre.trim().isEmpty) ? 'historial-entregas.xlsx' : nombre.trim();
}

// Único punto de la app que consulta el historial de entregas. El servidor ya
// ordena de la más reciente a la más antigua, filtra por el campus del usuario y
// busca por solicitante o folio (parcial, sin distinguir mayúsculas ni acentos).
class HistorialEntregasRepositorio {
  const HistorialEntregasRepositorio(this._dio);

  final Dio _dio;

  /// [consulta] filtra por solicitante o folio. El servidor exige al menos
  /// [minimoCaracteresBusqueda] caracteres: con menos (o vacía) no se manda `q`.
  /// [desde] y [hasta] son días calendario inclusivos en horario de Hermosillo.
  Future<Pagina<EntregaHistorial>> listar({
    required int pagina,
    required int porPagina,
    String consulta = '',
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final texto = consulta.trim();
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/boletas/historial',
        queryParameters: {
          if (texto.length >= minimoCaracteresBusqueda) 'q': texto,
          if (desde != null) 'desde': _fechaApi(desde),
          if (hasta != null) 'hasta': _fechaApi(hasta),
          'pagina': pagina,
          'porPagina': porPagina,
        },
      );
      final json = respuesta.data!;
      // El servidor responde solo { datos, total }: la página y su tamaño son los que se pidieron.
      return Pagina(
        items: [
          for (final f in json['datos'] as List<dynamic>)
            EntregaHistorial.fromJson(f as Map<String, dynamic>),
        ],
        total: (json['total'] as num?)?.toInt() ?? 0,
        pagina: pagina,
        porPagina: porPagina,
      );
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    }
  }

  /// Descarga en Excel las boletas que cumplen [consulta], sin paginar (AI-79).
  /// Igual que en [listar], con menos de [minimoCaracteresBusqueda] caracteres no
  /// se manda `q` y se exporta el historial completo.
  Future<ArchivoHistorial> exportar({String consulta = ''}) async {
    final texto = consulta.trim();
    try {
      final respuesta = await _dio.get<List<int>>(
        '/boletas/historial/exportar',
        queryParameters: {
          if (texto.length >= minimoCaracteresBusqueda) 'q': texto,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      return ArchivoHistorial(
        nombre: nombreDeArchivo(respuesta.headers.value('content-disposition')),
        bytes: Uint8List.fromList(respuesta.data ?? const []),
        total: int.tryParse(respuesta.headers.value('x-total-resultados') ?? '') ?? 0,
      );
    } on DioException catch (error) {
      throw _errorDeExportacion(error);
    }
  }

  // Al pedir bytes, Dio deja también el cuerpo de un error como bytes. Si es el
  // JSON de error del servidor ({ codigo, mensaje }) se lee para mostrar su mensaje.
  ErrorNegocio _errorDeExportacion(DioException error) {
    final datos = error.response?.data;
    if (error.error is! ErrorNegocio && datos is List<int>) {
      try {
        final json = jsonDecode(utf8.decode(datos));
        if (json is Map<String, dynamic>) {
          return ErrorNegocio.fromJson(json, estadoHttp: error.response?.statusCode);
        }
      } on FormatException {
        // No era JSON: se usa el mensaje genérico de abajo.
      }
    }
    return ErrorNegocio.desdeDio(error);
  }

  // El contrato del API exige AAAA-MM-DD, sin hora ni zona.
  static String _fechaApi(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';

  /// Detalle de una boleta: datos generales, materiales, herramientas y autorización.
  /// Si no existe o es de otro campus, el servidor responde 404 BOLETA_NO_EXISTE.
  Future<DetalleBoleta> detalle(int boletaId) async {
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>('/boletas/$boletaId/detalle');
      return DetalleBoleta.fromJson(respuesta.data!);
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    }
  }
}

final proveedorHistorialEntregasRepositorio = Provider<HistorialEntregasRepositorio>(
  (ref) => HistorialEntregasRepositorio(ref.watch(proveedorClienteApi)),
);

/// Detalle de la boleta con ese id. Se descarta al cerrar el diálogo (autoDispose),
/// así al volver a abrirlo se ve el estado actual de las herramientas.
final detalleBoletaProvider = FutureProvider.autoDispose.family<DetalleBoleta, int>(
  (ref, boletaId) => ref.read(proveedorHistorialEntregasRepositorio).detalle(boletaId),
);
