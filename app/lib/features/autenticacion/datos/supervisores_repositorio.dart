import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';

// Supervisor que puede autorizar una entrega (GET /usuarios/supervisores).
// [id] es el UUID del usuario: se manda como supervisorId al crear la boleta.
class Supervisor {
  const Supervisor({required this.id, required this.nombre, required this.rol});
  final String id;
  final String nombre;
  final String rol;

  factory Supervisor.fromJson(Map<String, dynamic> json) => Supervisor(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        rol: json['rol'] as String,
      );
}

class SupervisoresRepositorio {
  const SupervisoresRepositorio(this._dio);

  final Dio _dio;

  Future<List<Supervisor>> listar() async {
    try {
      final respuesta = await _dio.get<List<dynamic>>('/usuarios/supervisores');
      return [
        for (final f in respuesta.data ?? const []) Supervisor.fromJson(f as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw ErrorNegocio.desdeDio(e);
    }
  }
}

final proveedorSupervisoresRepositorio = Provider<SupervisoresRepositorio>(
  (ref) => SupervisoresRepositorio(ref.watch(proveedorClienteApi)),
);
