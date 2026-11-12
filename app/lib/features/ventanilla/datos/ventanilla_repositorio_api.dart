import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo_inventario/datos/catalogos.dart';
import '../../catalogo_inventario/datos/catalogos_repository.dart';
import '../../catalogo_inventario/datos/producto_resumen.dart';
import '../../catalogo_inventario/datos/productos_repository.dart';
import 'modelos.dart';
import 'ventanilla_repositorio.dart';

// Mínimo de caracteres para buscar materiales; es el mismo que valida el servidor.
const minimoCaracteresBusqueda = 2;

// Implementación de VentanillaRepositorio que usa la API real donde ya existe.
// AI-30 y AI-62: buscarMateriales va a GET /catalogo/productos y opcionesFiltros a
// GET /catalogo/categorias y /catalogo/almacenes. El resto de los métodos sigue en
// la implementación simulada de Denise porque sus endpoints todavía no existen
// (solicitantes, autorizadores, activos, validación y entrega); cada tarea los irá
// pasando a la API.
class VentanillaRepositorioApi implements VentanillaRepositorio {
  VentanillaRepositorioApi(
    this._productos, {
    required this._catalogos,
    VentanillaRepositorio? simulado,
  }) : _simulado = simulado ?? VentanillaRepositorioSimulado();

  final ProductosRepository _productos;
  final CatalogosRepository _catalogos;
  final VentanillaRepositorio _simulado;

  // La pantalla de Denise maneja los filtros por nombre; la API, por id. Se guardan
  // las equivalencias la primera vez que se cargan las opciones.
  Future<_IdsFiltros>? _ids;

  // Busca materiales con existencia. Reglas de AI-30 y AI-62:
  // - Sin texto lista lo que cumple los filtros (al abrir: "Más comunes").
  // - Con 1 carácter no se llama al servidor y la página queda vacía; la pantalla
  //   pide escribir más. Con 2 o más busca por código, nombre o alias.
  // - Los filtros se combinan entre sí y con el texto. Si "Más comunes" está
  //   seleccionado, el texto busca solo dentro de los más comunes (opción A).
  // - El servidor solo devuelve materiales con existencia.
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
    if (texto.isNotEmpty && texto.length < minimoCaracteresBusqueda) {
      return Pagina(items: const [], total: 0, pagina: pagina, porPagina: porPagina);
    }

    final ids = (categoria == null && almacen == null) ? null : await _cargarIds();
    final resultado = await _productos.buscar(
      texto: texto,
      categoriaId: categoria == null ? null : ids!.categorias[categoria],
      tipo: tipo == null ? null : codigoDeTipo(tipo),
      almacenId: almacen == null ? null : ids!.almacenes[almacen],
      soloMasComunes: soloComunes,
      pagina: pagina,
      limite: porPagina,
    );
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

  // Opciones de los desplegables: categorías y almacenes de la API; los tipos son
  // fijos. Los nombres de almacén repetidos en varios campus (supervisor jefe)
  // llevan el campus para distinguirlos: "Principal (Náinari)".
  @override
  Future<OpcionesFiltros> opcionesFiltros() async {
    final ids = await _cargarIds();
    return OpcionesFiltros(
      categorias: ids.categorias.keys.toList(growable: false),
      tipos: [for (final t in tiposProducto) t.etiqueta],
      almacenes: ids.almacenes.keys.toList(growable: false),
    );
  }

  // Carga categorías y almacenes una sola vez. Si falla, se olvida el intento para
  // que la siguiente llamada lo repita.
  Future<_IdsFiltros> _cargarIds() {
    return _ids ??= () async {
      try {
        // Las dos consultas van en paralelo; si una falla, sale su error tal cual
        // (un ErrorNegocio que la pantalla puede mostrar).
        final resultados = await Future.wait<Object>(
          [_catalogos.listarCategorias(), _catalogos.listarAlmacenes()],
          eagerError: true,
        );
        final categorias = resultados[0] as List<Categoria>;
        final almacenes = resultados[1] as List<Almacen>;
        return _IdsFiltros(
          categorias: {for (final c in categorias) c.nombre: c.id},
          almacenes: {for (final a in almacenes) nombreAlmacen(a, almacenes): a.id},
        );
      } catch (_) {
        _ids = null;
        rethrow;
      }
    }();
  }

  @override
  Future<Pagina<Solicitante>> buscarSolicitantes(String consulta, {int pagina = 1, int porPagina = 5}) =>
      _simulado.buscarSolicitantes(consulta, pagina: pagina, porPagina: porPagina);

  @override
  Future<List<Autorizador>> listarAutorizadores() => _simulado.listarAutorizadores();

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

// Equivalencias nombre → id de los filtros, en el orden en que llegan del servidor.
class _IdsFiltros {
  const _IdsFiltros({required this.categorias, required this.almacenes});
  final Map<String, int> categorias;
  final Map<String, int> almacenes;
}

// Código de la API para la etiqueta de tipo que muestra la pantalla; null si no existe.
String? codigoDeTipo(String etiqueta) {
  for (final t in tiposProducto) {
    if (t.etiqueta == etiqueta) return t.codigo;
  }
  return null;
}

// Nombre del almacén en el desplegable. Si otro almacén de [todos] se llama igual
// (otro campus), se agrega el campus: "Principal (Náinari)".
String nombreAlmacen(Almacen almacen, List<Almacen> todos) {
  final repetido = todos.any((a) => a.id != almacen.id && a.nombre == almacen.nombre);
  return repetido ? '${almacen.nombre} (${almacen.campus})' : almacen.nombre;
}

// Repositorio de ventanilla conectado a la API. main.dart lo usa en lugar del
// simulado cuando la app se ejecuta con API_URL (parte 6 de AI-30).
final ventanillaRepositorioApiProvider = Provider<VentanillaRepositorio>(
  (ref) => VentanillaRepositorioApi(
    ref.watch(proveedorProductosRepository),
    catalogos: ref.watch(proveedorCatalogosRepository),
  ),
);
