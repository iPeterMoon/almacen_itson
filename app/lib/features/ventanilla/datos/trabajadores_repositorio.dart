import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import '../../../core/red/pagina_api.dart';

// Zona de trabajo de un trabajador (GET /trabajadores).
class ZonaTrabajador {
  const ZonaTrabajador({required this.id, required this.nombre});
  final int id;
  final String nombre;

  factory ZonaTrabajador.fromJson(Map<String, dynamic> json) =>
      ZonaTrabajador(id: (json['id'] as num).toInt(), nombre: json['nombre'] as String);
}

// Trabajador tal como lo devuelve GET /trabajadores. [tipo] es 'ITSON' o 'COMPANIA';
// [dependencia], 'SERVICIOS_GENERALES' o 'MANTENIMIENTO'.
class Trabajador {
  const Trabajador({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.dependencia,
    this.compania,
    this.zonas = const [],
  });

  final int id;
  final String nombre;
  final String tipo;
  final String? compania;
  final String dependencia;
  final List<ZonaTrabajador> zonas;

  factory Trabajador.fromJson(Map<String, dynamic> json) => Trabajador(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        compania: json['compania'] as String?,
        dependencia: json['dependencia'] as String,
        zonas: [
          for (final z in (json['zonas'] as List<dynamic>? ?? const []))
            ZonaTrabajador.fromJson(z as Map<String, dynamic>),
        ],
      );
}

// Único punto de la app que llama a GET /trabajadores (solicitantes de la boleta).
class TrabajadoresRepositorio {
  const TrabajadoresRepositorio(this._dio);

  final Dio _dio;

  // [texto] vacío lista a todos; el servidor exige de 2 a 100 caracteres si viene.
  Future<PaginaApi<Trabajador>> buscar({String? texto, int? pagina, int? limite}) async {
    final t = texto?.trim();
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/trabajadores',
        queryParameters: {
          if (t != null && t.isNotEmpty) 'texto': t,
          'pagina': ?pagina,
          'limite': ?limite,
        },
      );
      return PaginaApi.fromJson(respuesta.data!, Trabajador.fromJson);
    } on DioException catch (e) {
      throw ErrorNegocio.desdeDio(e);
    }
  }
}

final proveedorTrabajadoresRepositorio = Provider<TrabajadoresRepositorio>(
  (ref) => TrabajadoresRepositorio(ref.watch(proveedorClienteApi)),
);
