import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import 'catalogos.dart';

// Lee los catálogos de los filtros de materiales (HU6, AI-62). Cualquier fallo sale
// como ErrorNegocio, con el mensaje en español que la pantalla puede mostrar.
class CatalogosRepository {
  const CatalogosRepository(this._dio);

  final Dio _dio;

  // Categorías activas, ordenadas por nombre.
  Future<List<Categoria>> listarCategorias() => _listar('/catalogo/categorias', Categoria.fromJson);

  // Almacenes activos de los campus del usuario (los limita el servidor), por nombre.
  Future<List<Almacen>> listarAlmacenes() => _listar('/catalogo/almacenes', Almacen.fromJson);

  Future<List<T>> _listar<T>(String ruta, T Function(Map<String, dynamic>) leer) async {
    try {
      final respuesta = await _dio.get<List<dynamic>>(ruta);
      return (respuesta.data ?? const [])
          .map((fila) => leer(fila as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    }
  }
}

final proveedorCatalogosRepository = Provider<CatalogosRepository>(
  (ref) => CatalogosRepository(ref.watch(proveedorClienteApi)),
);
