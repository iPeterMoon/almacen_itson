import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo_inventario/datos/producto_resumen.dart';
import '../../catalogo_inventario/datos/productos_repository.dart';
import 'modelos.dart';
import 'ventanilla_repositorio.dart';

// Mínimo de caracteres para buscar materiales; es el mismo que valida el servidor.
const minimoCaracteresBusqueda = 2;

// Implementación de VentanillaRepositorio que usa la API real donde ya existe.
// AI-30: buscarMateriales va a GET /catalogo/productos. El resto de los métodos
// sigue en la implementación simulada de Denise porque sus endpoints todavía no
// existen (solicitantes, autorizadores, filtros, activos, validación y entrega);
// cada tarea los irá pasando a la API.
class VentanillaRepositorioApi implements VentanillaRepositorio {
  VentanillaRepositorioApi(this._productos, {VentanillaRepositorio? simulado})
      : _simulado = simulado ?? VentanillaRepositorioSimulado();

  final ProductosRepository _productos;
  final VentanillaRepositorio _simulado;

  // Busca por código, nombre estándar o alias. Reglas de AI-30:
  // - Con menos de 2 caracteres no se llama al servidor y la página queda vacía;
  //   la pantalla pide escribir más.
  // - El servidor solo devuelve materiales con existencia.
  // - Los filtros (categoría, tipo, almacén y "Más comunes") se ignoran hasta AI-62.
  @override
  Future<Pagina<MaterialCatalogo>> buscarMateriales({
    String consulta = '',
    String? categoria,
    String? tipo,
    String? almacen,
    bool soloComunes = false,
    int pagina = 1,
    int porPagina = 5,
  }) async {
    final texto = consulta.trim();
    if (texto.length < minimoCaracteresBusqueda) {
      return Pagina(items: const [], total: 0, pagina: pagina, porPagina: porPagina);
    }

    final resultado = await _productos.buscar(texto: texto, pagina: pagina, limite: porPagina);
    final items = resultado.datos.map(aMaterialCatalogo).toList(growable: false);
    // TEMPORAL (AI-63): el servidor todavía no manda el total de coincidencias, así
    // que se cuenta solo lo recibido hasta esta página y el paginador no ofrece
    // una página siguiente.
    return Pagina(
      items: items,
      total: (pagina - 1) * porPagina + items.length,
      pagina: pagina,
      porPagina: porPagina,
    );
  }

  @override
  Future<Pagina<Solicitante>> buscarSolicitantes(String consulta, {int pagina = 1, int porPagina = 5}) =>
      _simulado.buscarSolicitantes(consulta, pagina: pagina, porPagina: porPagina);

  @override
  Future<List<Autorizador>> listarAutorizadores() => _simulado.listarAutorizadores();

  @override
  Future<OpcionesFiltros> opcionesFiltros() => _simulado.opcionesFiltros();

  @override
  Future<List<ActivoCatalogo>> buscarActivos(String consulta) => _simulado.buscarActivos(consulta);

  @override
  Future<AlertaRestriccion?> validarMaterial({
    String? solicitanteId,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) =>
      _simulado.validarMaterial(
        solicitanteId: solicitanteId,
        material: material,
        cantidad: cantidad,
        unidad: unidad,
      );

  @override
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega solicitud) =>
      _simulado.registrarEntrega(solicitud);
}

// Etiquetas que usa la pantalla para el tipo de producto.
const _etiquetasTipo = {
  'SERVICIOS_GENERALES': 'Servicios Generales',
  'MANTENIMIENTO': 'Mantenimiento',
  'AMBOS': 'Ambos',
};

// Convierte el producto de la API en el material que dibuja la pantalla de Denise.
MaterialCatalogo aMaterialCatalogo(ProductoResumen p) {
  return MaterialCatalogo(
    codigo: p.codigo,
    concepto: p.nombreEstandar,
    alias: p.alias ?? '',
    categoria: p.categoria,
    tipo: _etiquetasTipo[p.tipo] ?? p.tipo,
    esComun: p.masComunes,
    almacen: textoAlmacenes(p.ubicaciones),
    ubicacion: textoUbicaciones(p.ubicaciones),
    existencia: p.existencia,
    unidadBase: p.unidad,
    // TEMPORAL (AI-29): la API todavía no manda las presentaciones de entrega
    // (medio litro, galón, caja...), así que solo se ofrece la unidad base. El
    // modal "Agregar Material" necesita al menos una unidad.
    unidades: [p.unidad],
  );
}

// Columna "Almacén": los almacenes donde hay existencia, sin repetir y en el orden
// del servidor. Ejemplo: "Almacén 1, Almacén 2". Sin ubicaciones: "-".
String textoAlmacenes(List<UbicacionProducto> ubicaciones) {
  final nombres = <String>{for (final u in ubicaciones) u.almacen};
  return nombres.isEmpty ? '-' : nombres.join(', ');
}

// Campo "Ubicación" del modal: la descripción dentro del almacén. Si hay varios
// almacenes, se indica a cuál pertenece cada una. Ejemplo: "Almacén 1: E1F1".
// Las ubicaciones sin descripción se omiten; si no queda ninguna: "-".
String textoUbicaciones(List<UbicacionProducto> ubicaciones) {
  final variosAlmacenes = {for (final u in ubicaciones) u.almacen}.length > 1;
  final textos = [
    for (final u in ubicaciones)
      if (u.ubicacion != null && u.ubicacion!.trim().isNotEmpty)
        variosAlmacenes ? '${u.almacen}: ${u.ubicacion}' : u.ubicacion!,
  ];
  return textos.isEmpty ? '-' : textos.join(', ');
}

// Repositorio de ventanilla conectado a la API. main.dart lo usa en lugar del
// simulado cuando la app se ejecuta con API_URL (parte 6 de AI-30).
final ventanillaRepositorioApiProvider = Provider<VentanillaRepositorio>(
  (ref) => VentanillaRepositorioApi(ref.watch(proveedorProductosRepository)),
);
