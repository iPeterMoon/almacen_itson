import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
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

  // El contrato del API exige AAAA-MM-DD, sin hora ni zona.
  static String _fechaApi(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';
}

final proveedorHistorialEntregasRepositorio = Provider<HistorialEntregasRepositorio>(
  (ref) => HistorialEntregasRepositorio(ref.watch(proveedorClienteApi)),
);
