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

class ActivosRepositorio {
  const ActivosRepositorio(this._dio);

  final Dio _dio;

  // [estado] 'DISPONIBLE' trae solo los que se pueden prestar.
  Future<PaginaApi<Activo>> buscar({String? texto, String? estado, int? limite}) async {
    final t = texto?.trim();
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/activos',
        queryParameters: {
          if (t != null && t.isNotEmpty) 'texto': t,
          'estado': ?estado,
          'limite': ?limite,
        },
      );
      return PaginaApi.fromJson(respuesta.data!, Activo.fromJson);
    } on DioException catch (e) {
      throw ErrorNegocio.desdeDio(e);
    }
  }
}

final proveedorActivosRepositorio = Provider<ActivosRepositorio>(
  (ref) => ActivosRepositorio(ref.watch(proveedorClienteApi)),
);
