import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../autenticacion/datos/supervisores_repositorio.dart';
import '../../autenticacion/presentacion/sesion_controlador.dart';
import '../../catalogo_inventario/datos/catalogos.dart';
import '../../catalogo_inventario/datos/catalogos_repository.dart';
import '../../catalogo_inventario/datos/producto_resumen.dart';
import '../../catalogo_inventario/datos/productos_repository.dart';
import '../../prestamos/datos/activos_repositorio.dart';
import 'boletas_repositorio.dart';
import 'modelos.dart';
import 'trabajadores_repositorio.dart';
import 'ventanilla_repositorio.dart';

// Mínimo de caracteres para buscar materiales; es el mismo que valida el servidor.
const minimoCaracteresBusqueda = 2;

// Implementación de VentanillaRepositorio que usa la API real donde ya existe:
// - buscarMateriales: GET /catalogo/productos (AI-30, AI-62).
// - opcionesFiltros: GET /catalogo/categorias y /catalogo/almacenes.
// - buscarSolicitantes: GET /trabajadores.
// - listarAutorizadores: GET /usuarios/supervisores.
// - buscarActivos: GET /activos?estado=DISPONIBLE.
// - validarMaterial: POST /boletas/validar-material.
// - registrarEntrega: POST /boletas/firmas, POST /boletas y GET /boletas/:id.
class VentanillaRepositorioApi implements VentanillaRepositorio {
  VentanillaRepositorioApi(
    this._productos, {
    required this._catalogos,
    required this._boletas,
    required this._trabajadores,
    required this._supervisores,
    required this._activos,
    String Function()? entregadoPor,
  }) : _entregadoPor = entregadoPor ?? (() => '');

  final ProductosRepository _productos;
  final CatalogosRepository _catalogos;
  final BoletasRepositorio _boletas;
  final TrabajadoresRepositorio _trabajadores;
  final SupervisoresRepositorio _supervisores;
  final ActivosRepositorio _activos;
  // Nombre del usuario con sesión; aparece como "Entregado por" en el resumen.
  final String Function() _entregadoPor;

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

  // Trabajadores registrados. Igual que en materiales: sin texto lista a todos y
  // con 1 carácter no se llama al servidor (pide de 2 a 100).
  @override
  Future<Pagina<Solicitante>> buscarSolicitantes(String consulta, {int pagina = 1, int porPagina = 5}) async {
    final texto = consulta.trim();
    if (texto.isNotEmpty && texto.length < minimoCaracteresBusqueda) {
      return Pagina(items: const [], total: 0, pagina: pagina, porPagina: porPagina);
    }
    final r = await _trabajadores.buscar(texto: texto, pagina: pagina, limite: porPagina);
    return Pagina(
      items: r.datos.map(aSolicitante).toList(growable: false),
      total: r.total,
      pagina: pagina,
      porPagina: porPagina,
    );
  }

  // Supervisores del campus: los mismos sirven para "Autorizó" y para autorizar
  // excepciones (su id es el UUID que pide crear_boleta).
  @override
  Future<List<Autorizador>> listarAutorizadores() async {
    final lista = await _supervisores.listar();
    return [for (final s in lista) Autorizador(id: s.id, nombre: s.nombre)];
  }

  // Solo activos DISPONIBLE: los demás no se pueden prestar. La lista de la
  // pantalla no tiene paginador, así que se piden hasta 20.
  @override
  Future<List<ActivoCatalogo>> buscarActivos(String consulta) async {
    final texto = consulta.trim();
    if (texto.isNotEmpty && texto.length < minimoCaracteresBusqueda) return const [];
    final r = await _activos.buscar(texto: texto, estado: 'DISPONIBLE', limite: 20);
    return r.datos.map(aActivoCatalogo).toList(growable: false);
  }

  // POST /boletas/validar-material. Si no alcanza la existencia lanza
  // STOCK_INSUFICIENTE (el diálogo muestra el mensaje y no agrega el material).
  // Si se rompe la periodicidad o el límite de la zona devuelve la alerta para
  // pedir motivo y autorización. Esas dos reglas solo se revisan con un
  // trabajador registrado; con uno sin registro solo cuenta la existencia.
  // La cantidad va en la unidad base: la app aún no maneja presentaciones (AI-29).
  @override
  Future<AlertaRestriccion?> validarMaterial({
    Solicitante? solicitante,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    final v = await _boletas.validarMaterial(
      productoId: _idDeProducto(material),
      cantidad: redondearCantidad(cantidad),
      trabajadorId: _idDeTrabajador(solicitante),
      zonaId: solicitante?.zonaId,
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
  // 3. Lee la fecha de entrega (GET /boletas/:id) para el resumen. Para entonces
  //    la boleta ya existe: si esta lectura falla se usa la hora del dispositivo,
  //    porque mostrar un error haría que se volviera a confirmar y se duplicara.
  // Si algún material necesita autorización, la base deja la boleta PENDIENTE: no
  // descuenta nada y el resumen lo indica (el folio ya existe, no se registra otra vez).
  @override
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega solicitud) async {
    // El servidor no guarda comentarios por herramienta; los de materiales sí.
    final herramientas = [
      for (final a in solicitud.activos)
        {'activoId': _idDeActivo(a.activo), 'diasPrestamo': a.dias},
    ];
    final materiales = [
      for (final m in solicitud.materiales)
        {
          'productoId': _idDeProducto(m.material),
          'cantidad': redondearCantidad(m.cantidad),
          if (m.comentario != null && m.comentario!.isNotEmpty) 'comentario': m.comentario,
          if (m.autorizacion != null) 'motivoExcepcion': _motivo(m.autorizacion!),
        },
    ];
    final supervisor = _supervisorId(solicitud.materiales);

    final rutas = await Future.wait([
      _boletas.subirFirma(solicitud.firmaRecibe, TipoFirma.recibe),
      _boletas.subirFirma(solicitud.firmaEntrega, TipoFirma.entrega),
    ]);

    // Registrado: la base toma nombre y zona del trabajador. Sin registro: nombre
    // y unidad capturados.
    final trabajadorId = _idDeTrabajador(solicitud.solicitante);
    final nombre = solicitud.solicitante?.nombre ?? solicitud.nombreSinRegistro ?? '';
    final unidad = solicitud.solicitante?.dependencia ?? solicitud.unidadSinRegistro ?? '';
    final numero = solicitud.numeroSolicitud?.trim();
    final boleta = await _boletas.crear({
      'materiales': materiales,
      if (herramientas.isNotEmpty) 'herramientas': herramientas,
      if (trabajadorId != null) ...{
        'trabajadorId': trabajadorId,
        'zonaId': ?solicitud.solicitante?.zonaId,
      } else ...{
        'solicitanteNombre': nombre,
        'solicitanteUnidad': unidad,
      },
      if (numero != null && numero.isNotEmpty) 'numeroSolicitud': numero,
      if (solicitud.autorizoNombre != null) 'autorizoNombre': solicitud.autorizoNombre,
      'supervisorId': ?supervisor,
      'firmaRecibe': rutas[0],
      'firmaEntrega': rutas[1],
    });

    final pendiente = boleta.estado == BoletaCreada.pendienteAutorizacion;
    final entregadoEn = pendiente ? null : await _fechaEntrega(boleta.boletaId);
    return ResumenEntrega(
      folio: boleta.folio,
      autorizacionPendiente: pendiente,
      recibidoPor: nombre,
      area: unidad,
      fechaHora: pendiente ? 'Pendiente de autorización' : formatearHoraFecha(entregadoEn),
      entregadoPor: _entregadoPor(),
      materiales: [
        for (final m in solicitud.materiales)
          LineaResumen(m.material.codigo, m.material.alias, m.cantidadTexto),
      ],
      activos: [
        for (final a in solicitud.activos)
          LineaResumen(a.activo.codigo, a.activo.equipo, a.activo.modelo, a.activo.serie),
      ],
    );
  }

  Future<String?> _fechaEntrega(int boletaId) async {
    try {
      return await _boletas.fechaEntrega(boletaId);
    } catch (_) {
      return DateTime.now().toUtc().toIso8601String();
    }
  }

  // Id del trabajador para el servidor; null si no hay solicitante registrado.
  int? _idDeTrabajador(Solicitante? s) => s == null ? null : int.tryParse(s.id);

  int _idDeActivo(ActivoCatalogo activo) {
    final id = activo.activoId;
    if (id == null) {
      throw ErrorNegocio(
        'ACTIVO_NO_ENCONTRADO',
        'La herramienta ${activo.codigo} no está registrada en el servidor.',
      );
    }
    return id;
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

  // Supervisor que autorizará las excepciones: el primero que se eligió en la
  // boleta (la base guarda una sola autorización por boleta). Si la base requiere
  // autorización sin supervisor, responde AUTORIZADOR_REQUERIDO.
  String? _supervisorId(List<ItemMaterial> materiales) {
    for (final m in materiales) {
      final id = m.autorizacion?.autorizadorId;
      if (id != null) return id;
    }
    return null;
  }
}

const _etiquetasDependencia = {
  'SERVICIOS_GENERALES': 'Servicios Generales',
  'MANTENIMIENTO': 'Mantenimiento',
};

// Convierte el trabajador de la API en el solicitante que dibuja la pantalla.
// "Zona" muestra todas sus zonas; "Área de trabajo" 1 y 2, las dos primeras. Si
// tiene una sola zona se guarda su id para validar el límite de la zona.
Solicitante aSolicitante(Trabajador t) {
  final zonas = [for (final z in t.zonas) z.nombre];
  return Solicitante(
    id: '${t.id}',
    nombre: t.nombre,
    dependencia: _etiquetasDependencia[t.dependencia] ?? t.dependencia,
    tipo: t.tipo == 'COMPANIA' ? (t.compania ?? 'Compañía') : 'ITSON',
    zona: zonas.isEmpty ? '-' : zonas.join(', '),
    areaTrabajo: zonas.isNotEmpty ? zonas[0] : null,
    areaTrabajo2: zonas.length > 1 ? zonas[1] : null,
    zonaId: t.zonas.length == 1 ? t.zonas.single.id : null,
  );
}

// Convierte el activo de la API en el que dibuja la lista de herramientas.
ActivoCatalogo aActivoCatalogo(Activo a) => ActivoCatalogo(
      activoId: a.id,
      codigo: a.codigo,
      equipo: a.nombre,
      modelo: a.modelo,
      serie: a.numeroSerie,
      almacen: a.almacen ?? '-',
      ubicacion: a.ubicacion ?? '-',
    );

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
    trabajadores: ref.watch(proveedorTrabajadoresRepositorio),
    supervisores: ref.watch(proveedorSupervisoresRepositorio),
    activos: ref.watch(proveedorActivosRepositorio),
    entregadoPor: () => ref.read(controladorSesionProvider).value?.usuario.nombre ?? '',
  ),
);
