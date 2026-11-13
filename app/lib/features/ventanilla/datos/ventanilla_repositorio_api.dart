import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../autenticacion/presentacion/sesion_controlador.dart';
import '../../catalogo_inventario/datos/catalogos.dart';
import '../../catalogo_inventario/datos/catalogos_repository.dart';
import '../../catalogo_inventario/datos/producto_resumen.dart';
import '../../catalogo_inventario/datos/productos_repository.dart';
import 'boletas_repositorio.dart';
import 'modelos.dart';
import 'ventanilla_repositorio.dart';

// Mínimo de caracteres para buscar materiales; es el mismo que valida el servidor.
const minimoCaracteresBusqueda = 2;

// Implementación de VentanillaRepositorio que usa la API real donde ya existe:
// - buscarMateriales: GET /catalogo/productos (AI-30, AI-62).
// - opcionesFiltros: GET /catalogo/categorias y /catalogo/almacenes.
// - validarMaterial: POST /boletas/validar-material.
// - registrarEntrega: POST /boletas/firmas, POST /boletas y GET /boletas/:id.
// Solicitantes, autorizadores y activos siguen en la implementación simulada de
// Denise porque el servidor todavía no tiene esos endpoints.
class VentanillaRepositorioApi implements VentanillaRepositorio {
  VentanillaRepositorioApi(
    this._productos, {
    required this._catalogos,
    required this._boletas,
    String Function()? entregadoPor,
    VentanillaRepositorio? simulado,
  })  : _entregadoPor = entregadoPor ?? (() => ''),
        _simulado = simulado ?? VentanillaRepositorioSimulado();

  final ProductosRepository _productos;
  final CatalogosRepository _catalogos;
  final BoletasRepositorio _boletas;
  // Nombre del usuario con sesión; aparece como "Entregado por" en el resumen.
  final String Function() _entregadoPor;
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
    // El total viene del servidor (AI-63): cuántos materiales cumplen el texto y los
    // filtros en todas las páginas. Con él el paginador de Denise calcula las páginas.
    return Pagina(
      items: items,
      total: resultado.total,
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

  // POST /boletas/validar-material. Si no alcanza la existencia lanza
  // STOCK_INSUFICIENTE (el diálogo muestra el mensaje y no agrega el material).
  // Si se rompe la periodicidad o el límite de la zona devuelve la alerta para
  // pedir motivo y autorización.
  // TEMPORAL: los solicitantes aún son simulados (no hay endpoint de trabajadores),
  // así que no se manda trabajadorId ni zonaId y el servidor solo revisa la
  // existencia. Cuando exista ese endpoint, mandar ambos para validar la HU6 E8/E10.
  // La cantidad va en la unidad base: la app aún no maneja presentaciones (AI-29).
  @override
  Future<AlertaRestriccion?> validarMaterial({
    String? solicitanteId,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    final v = await _boletas.validarMaterial(
      productoId: _idDeProducto(material),
      cantidad: cantidad,
    );
    if (!v.stockSuficiente) {
      final disponible = '${formatearCantidad(v.cantidadSugerida ?? v.disponible)} ${material.unidadBase}';
      throw ErrorNegocio(
        'STOCK_INSUFICIENTE',
        'No hay existencia suficiente de ${material.concepto}: '
            'solicitaste ${formatearCantidad(cantidad)} $unidad y hay $disponible.',
        datos: {'disponible': v.cantidadSugerida ?? v.disponible},
      );
    }
    final regla = v.limiteCantidad == null
        ? ''
        : '${formatearCantidad(v.limiteCantidad!)} ${material.unidadBase} '
            'cada ${v.limiteCadaDias} días';
    if (v.excedePeriodicidad) {
      return AlertaRestriccion(
        tipo: TipoAlerta.periodicidad,
        titulo: 'Periodicidad no cumplida',
        regla: regla,
        ultimaEntrega: formatearHoraFecha(v.ultimaEntrega),
        proximaEntrega: formatearFecha(v.proximaEntrega),
        diasFaltantes: v.diasFaltantes,
      );
    }
    if (v.excedeLimite) {
      return AlertaRestriccion(
        tipo: TipoAlerta.limiteZona,
        titulo: 'Límite de la zona',
        regla: 'Máximo $regla',
        entregado: '${formatearCantidad(v.entregadoPeriodo)} ${material.unidadBase}',
        solicitado: '${formatearCantidad(cantidad)} $unidad',
      );
    }
    return null;
  }

  // Registra la boleta en el servidor en tres pasos:
  // 1. Sube las dos firmas (POST /boletas/firmas) y obtiene sus rutas.
  // 2. Crea la boleta (POST /boletas). La base valida stock, descuenta
  //    existencias y genera el folio en una sola transacción.
  // 3. Lee la fecha de entrega (GET /boletas/:id) para el resumen.
  @override
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega solicitud) async {
    // TEMPORAL: los activos aún son simulados (no hay endpoint de activos) y no
    // tienen id del servidor. Se avisa en lugar de omitirlos sin decir nada.
    if (solicitud.activos.isNotEmpty) {
      throw const ErrorNegocio(
        'HERRAMIENTAS_NO_CONECTADAS',
        'El préstamo de herramientas todavía no está conectado al servidor. '
            'Desmarca o quita las herramientas para registrar los materiales.',
      );
    }
    final materiales = [
      for (final m in solicitud.materiales)
        {
          'productoId': _idDeProducto(m.material),
          'cantidad': m.cantidad,
          if (m.comentario != null && m.comentario!.isNotEmpty) 'comentario': m.comentario,
          if (m.autorizacion != null) 'motivoExcepcion': _motivo(m.autorizacion!),
        },
    ];
    final supervisor = _supervisorId(solicitud.materiales);

    final rutas = await Future.wait([
      _boletas.subirFirma(solicitud.firmaRecibe, TipoFirma.recibe),
      _boletas.subirFirma(solicitud.firmaEntrega, TipoFirma.entrega),
    ]);

    // TEMPORAL: el solicitante registrado viene de la lista simulada y su id no
    // existe en el servidor; se manda como "sin registro" con su nombre y
    // dependencia. Cuando exista el endpoint de trabajadores, mandar trabajadorId.
    final nombre = solicitud.solicitante?.nombre ?? solicitud.nombreSinRegistro ?? '';
    final unidad = solicitud.solicitante?.dependencia ?? solicitud.unidadSinRegistro ?? '';
    final numero = solicitud.numeroSolicitud?.trim();
    final boleta = await _boletas.crear({
      'materiales': materiales,
      'solicitanteNombre': nombre,
      'solicitanteUnidad': unidad,
      if (numero != null && numero.isNotEmpty) 'numeroSolicitud': numero,
      if (solicitud.autorizoNombre != null) 'autorizoNombre': solicitud.autorizoNombre,
      'supervisorId': ?supervisor,
      'firmaRecibe': rutas[0],
      'firmaEntrega': rutas[1],
    });

    if (boleta.estado == BoletaCreada.pendienteAutorizacion) {
      throw ErrorNegocio(
        'BOLETA_PENDIENTE_AUTORIZACION',
        'La boleta ${boleta.folio} quedó registrada y pendiente de autorización del '
            'supervisor. No la registres otra vez: se entregará cuando la autoricen.',
      );
    }

    final entregadoEn = await _boletas.fechaEntrega(boleta.boletaId);
    return ResumenEntrega(
      folio: boleta.folio,
      recibidoPor: nombre,
      area: unidad,
      fechaHora: formatearHoraFecha(entregadoEn),
      entregadoPor: _entregadoPor(),
      materiales: [
        for (final m in solicitud.materiales)
          LineaResumen(m.material.codigo, m.material.alias, m.cantidadTexto),
      ],
      activos: const [],
    );
  }

  // Los materiales de la API siempre traen productoId; uno sin él vendría del
  // repositorio simulado, que no existe en el servidor.
  int _idDeProducto(MaterialCatalogo material) {
    final id = material.productoId;
    if (id == null) {
      throw ErrorNegocio(
        'PRODUCTO_NO_REGISTRADO',
        'El material ${material.codigo} no está registrado en el servidor.',
      );
    }
    return id;
  }

  String _motivo(Autorizacion a) {
    final detalle = a.detalleOtro?.trim();
    return detalle == null || detalle.isEmpty ? a.motivo : '${a.motivo}: $detalle';
  }

  // Supervisor que autorizará las excepciones. TEMPORAL: los autorizadores aún
  // son simulados y sus ids no son UUID del servidor; solo se manda un UUID real.
  // Si la base requiere autorización sin supervisor, responde AUTORIZADOR_REQUERIDO.
  String? _supervisorId(List<ItemMaterial> materiales) {
    for (final m in materiales) {
      final id = m.autorizacion?.autorizadorId;
      if (id != null && _patronUuid.hasMatch(id)) return id;
    }
    return null;
  }
}

final _patronUuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

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
    productoId: p.id,
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
    boletas: ref.watch(proveedorBoletasRepositorio),
    entregadoPor: () => ref.read(controladorSesionProvider).value?.usuario.nombre ?? '',
  ),
);
