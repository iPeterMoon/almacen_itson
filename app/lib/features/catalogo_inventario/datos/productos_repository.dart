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

  // Busca productos con existencia en los campus del usuario. Todo es opcional y
  // se combina (AI-62):
  // - [texto]: código, nombre estándar o alias; el servidor exige 2 a 100
  //   caracteres. Vacío o nulo no se manda (lista sin filtrar por texto).
  // - [categoriaId] y [almacenId]: ids de GET /catalogo/categorias y /almacenes.
  // - [tipo]: 'SERVICIOS_GENERALES' o 'MANTENIMIENTO' (ver tiposProducto).
  // - [soloMasComunes]: solo los marcados como "Más comunes".
  // Sin [limite] el servidor usa 8. [pagina] y [limite] son para AI-63.
  Future<ResultadoBusquedaProductos> buscar({
    String? texto,
    int? categoriaId,
    String? tipo,
    int? almacenId,
    bool soloMasComunes = false,
    int? pagina,
    int? limite,
  }) async {
    final textoLimpio = texto?.trim();
    try {
      final respuesta = await _dio.get<Map<String, dynamic>>(
        '/catalogo/productos',
        queryParameters: {
          if (textoLimpio != null && textoLimpio.isNotEmpty) 'texto': textoLimpio,
          'categoriaId': ?categoriaId,
          'tipo': ?tipo,
          'almacenId': ?almacenId,
          if (soloMasComunes) 'soloMasComunes': 'true',
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
