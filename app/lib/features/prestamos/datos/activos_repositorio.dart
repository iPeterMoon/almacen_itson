import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import '../../../core/red/pagina_api.dart';

// Activo (herramienta o equipo) tal como lo devuelve GET /activos.
class Activo {
  const Activo({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.modelo,
    required this.numeroSerie,
    required this.estado,
    this.almacen,
    this.ubicacion,
  });

  final int id;
  final String codigo;
  final String nombre;
  final String modelo;
  final String numeroSerie;
  // 'DISPONIBLE', 'EN_PRESTAMO', 'EN_REPARACION', 'ROBO_EXTRAVIO' o 'DE_BAJA'.
  final String estado;
  final String? almacen;
  final String? ubicacion;

  factory Activo.fromJson(Map<String, dynamic> json) => Activo(
        id: (json['id'] as num).toInt(),
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        modelo: json['modelo'] as String,
        numeroSerie: json['numeroSerie'] as String,
        estado: json['estado'] as String,
        almacen: (json['almacen'] as Map<String, dynamic>?)?['nombre'] as String?,
        ubicacion: json['ubicacion'] as String?,
      );
}

// Respuesta de POST /activos/validar (HU8 E2, E3 y E5). No registra nada.
// [prestable] es true solo si el activo está DISPONIBLE. Si está prestado trae el
// custodio y la fecha prevista (ISO 8601). [solicitanteConVencido] solo avisa.
class ValidacionActivoApi {
  const ValidacionActivoApi({
    required this.activo,
    required this.prestable,
    required this.solicitanteConVencido,
    this.motivo,
    this.custodio,
    this.fechaPrevista,
    this.prestadoEn,
  });

  // id, codigo, nombre, modelo, numeroSerie y estado del activo validado.
  final Activo activo;
  final bool prestable;
  final bool solicitanteConVencido;
  // 'PRESTADO' o 'NO_DISPONIBLE' cuando no es prestable.
  final String? motivo;
  final String? custodio;
  final String? fechaPrevista;
  // SUPUESTO: el servidor aún no lo manda; si llega se muestra la fecha y hora del préstamo.
  final String? prestadoEn;

  factory ValidacionActivoApi.fromJson(Map<String, dynamic> json) => ValidacionActivoApi(
        activo: Activo.fromJson(json['activo'] as Map<String, dynamic>),
        prestable: json['prestable'] as bool,
        solicitanteConVencido: json['solicitanteConVencido'] as bool? ?? false,
        motivo: json['motivo'] as String?,
        custodio: json['custodio'] as String?,
        fechaPrevista: json['fechaPrevista'] as String?,
        prestadoEn: json['prestadoEn'] as String?,
      );
}

class ActivosRepositorio {
  const ActivosRepositorio(this._dio);

  final Dio _dio;

  // [soloPrestables] true trae solo los DISPONIBLE, para la boleta.
  // [estado] se conserva por compatibilidad con quienes aún filtran por estado.
  Future<PaginaApi<Activo>> buscar({
    String? texto,
    bool? soloPrestables,
    String? estado,
    int? pagina,
    int? limite,
  }) async {
    final t = texto?.trim();
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/activos',
        queryParameters: {
          if (t != null && t.isNotEmpty) 'texto': t,
          'soloPrestables': ?soloPrestables,
          'estado': ?estado,
          'pagina': ?pagina,
          'limite': ?limite,
        },
      );
      return PaginaApi.fromJson(respuesta.data!, Activo.fromJson);
    } on DioException catch (e) {
      throw ErrorNegocio.desdeDio(e);
    }
  }

  // Valida un activo antes de prestarlo. Con [trabajadorId] también revisa si el
  // solicitante tiene préstamos vencidos. Si el código no existe en los campus del
  // usuario lanza ErrorNegocio ACTIVO_NO_ENCONTRADO (404).
  Future<ValidacionActivoApi> validar({required String codigo, int? trabajadorId}) async {
    try {
      final respuesta = await _dio.post<Map<String, dynamic>>(
        '/activos/validar',
        data: {'codigo': codigo, 'trabajadorId': ?trabajadorId},
      );
      return ValidacionActivoApi.fromJson(respuesta.data!);
    } on DioException catch (e) {
      throw ErrorNegocio.desdeDio(e);
    }
  }
}

final proveedorActivosRepositorio = Provider<ActivosRepositorio>(
  (ref) => ActivosRepositorio(ref.watch(proveedorClienteApi)),
);
