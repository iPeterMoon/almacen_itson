import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';
import 'producto_resumen.dart';

// Único punto de la app que llama a las rutas de productos del servidor. Los
// productos son del módulo de catálogo; ventanilla los consume a través de
// este repositorio (AI-30). Cualquier fallo sale como ErrorNegocio, con el
// mensaje en español que la pantalla puede mostrar.
class ProductosRepository {
  const ProductosRepository(this._dio);

  final Dio _dio;

  // Busca por código, nombre estándar o alias. El servidor solo devuelve
  // productos con existencia en los campus del usuario y valida el texto
  // (2 a 100 caracteres); sin [limite] usa 8. [pagina] y [limite] quedan para
  // la paginación (AI-63).
  Future<ResultadoBusquedaProductos> buscar({
    required String texto,
    int? pagina,
    int? limite,
  }) async {
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/catalogo/productos',
        queryParameters: {
          'texto': texto,
          'pagina': ?pagina,
          'limite': ?limite,
        },
      );
      return ResultadoBusquedaProductos.fromJson(respuesta.data!);
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    }
  }
}

final proveedorProductosRepository = Provider<ProductosRepository>(
  (ref) => ProductosRepository(ref.watch(proveedorClienteApi)),
);
