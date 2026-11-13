import '../../../core/errores/error_negocio.dart';
import 'modelos.dart';

/// Contrato que usa la pantalla. La implementación real llamará a la API NestJS con dio.
///
/// SUPUESTOS DE ENDPOINTS (confirmar con backend en /docs):
///   GET  /api/v1/ventanilla/solicitantes?q=&pagina=&porPagina=   -> { items, total }
///   GET  /api/v1/ventanilla/autorizadores
///   GET  /api/v1/inventario/materiales?q=&categoria=&tipo=&almacen=&comunes=&pagina=&porPagina=   -> { items, total }
///   GET  /api/v1/inventario/activos?q=
///   POST /api/v1/ventanilla/materiales/validar   -> alerta de periodicidad / límite de zona
///   POST /api/v1/ventanilla/entregas             -> folio y resumen (descuenta stock)
abstract class VentanillaRepositorio {
  Future<Pagina<Solicitante>> buscarSolicitantes(String consulta, {int pagina = 1, int porPagina = 5});
  Future<List<Autorizador>> listarAutorizadores();
  Future<OpcionesFiltros> opcionesFiltros();
  Future<Pagina<MaterialCatalogo>> buscarMateriales({
    String consulta = '',
    String? categoria,
    String? tipo,
    String? almacen,
    bool soloComunes = false,
    int pagina = 1,
    int porPagina = 5,
  });
  Future<List<ActivoCatalogo>> buscarActivos(String consulta);

  /// Devuelve null si no hay restricción; si la hay, la alerta a mostrar.
  Future<AlertaRestriccion?> validarMaterial({
    Solicitante? solicitante,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  });

  /// Lanza [ErrorNegocio] (ej. STOCK_INSUFICIENTE) si el servidor rechaza la boleta.
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega solicitud);
}

/// Implementación SIMULADA para desarrollar la UI sin servidor.
/// Reemplazar por VentanillaRepositorioApi cuando exista el contrato.
class VentanillaRepositorioSimulado implements VentanillaRepositorio {
  int _folio = 184;

  static const _solicitantes = [
    Solicitante(id: '1', nombre: 'Pedro Luna Olivarría', dependencia: 'Servicios Generales', tipo: 'ITSON', zona: 'Taller Principal', areaTrabajo: 'Mantenimiento', areaTrabajo2: 'Taller Principal'),
    Solicitante(id: '2', nombre: 'Miguel Angel', dependencia: 'Servicios Generales', tipo: 'ITSON', zona: 'AV 1800', areaTrabajo: 'Mantenimiento', areaTrabajo2: 'AV 1800'),
    Solicitante(id: '3', nombre: 'Ana Lizbeth', dependencia: 'Mantenimiento', tipo: 'Compañía', zona: 'Polideportivo', areaTrabajo: 'Mantenimiento', areaTrabajo2: 'Polideportivo'),
    Solicitante(id: '4', nombre: 'Nayeli Solis', dependencia: 'Servicios Generales', tipo: 'ITSON', zona: 'Tutoria', areaTrabajo: 'Servicios', areaTrabajo2: 'Tutoria'),
    Solicitante(id: '5', nombre: 'Rosa Molina', dependencia: 'Maxi Servicios', tipo: 'ITSON', zona: 'Video conferencias', areaTrabajo: 'Servicios', areaTrabajo2: 'Video conferencias'),
    Solicitante(id: '6', nombre: 'Luis Parra', dependencia: 'Mantenimiento', tipo: 'ITSON', zona: 'Gimnasio', areaTrabajo: 'Mantenimiento', areaTrabajo2: 'Gimnasio'),
    Solicitante(id: '7', nombre: 'Carmen Soto', dependencia: 'Servicios Generales', tipo: 'Compañía', zona: 'Biblioteca', areaTrabajo: 'Servicios', areaTrabajo2: 'Biblioteca'),
    Solicitante(id: '8', nombre: 'Jorge Ibarra', dependencia: 'Maxi Servicios', tipo: 'ITSON', zona: 'Cafetería', areaTrabajo: 'Servicios', areaTrabajo2: 'Cafetería'),
    Solicitante(id: '9', nombre: 'Daniela Ochoa', dependencia: 'Mantenimiento', tipo: 'ITSON', zona: 'Laboratorios', areaTrabajo: 'Mantenimiento', areaTrabajo2: 'Laboratorios'),
    Solicitante(id: '10', nombre: 'Ramón Acosta', dependencia: 'Servicios Generales', tipo: 'ITSON', zona: 'Estacionamiento', areaTrabajo: 'Servicios', areaTrabajo2: 'Estacionamiento'),
    Solicitante(id: '11', nombre: 'Sofía Valdez', dependencia: 'Maxi Servicios', tipo: 'Compañía', zona: 'Auditorio', areaTrabajo: 'Servicios', areaTrabajo2: 'Auditorio'),
  ];

  static const _autorizadores = [
    Autorizador(id: 'a1', nombre: 'Leonel Lares'),
    Autorizador(id: 'a2', nombre: 'Alicia Garcia'),
    Autorizador(id: 'a3', nombre: 'Juan Lopez'),
    Autorizador(id: 'a4', nombre: 'Martin Flores'),
  ];

  static const _litros = ['Medio litros', 'Litros', 'Galones'];
  static const _materiales = [
    MaterialCatalogo(codigo: 'CD-123', concepto: 'Limpiador multiusos', alias: 'Pinol', tipo: 'Servicios Generales', esComun: true, categoria: 'Líquido', almacen: 'Dormitorios', ubicacion: 'Estante 2', existencia: 12, unidadBase: 'litros', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-374', concepto: 'Diluyente', alias: 'Thinner 2203', tipo: 'Mantenimiento', esComun: false, categoria: 'Líquido', almacen: 'Mantenimiento', ubicacion: '-', existencia: 8, unidadBase: 'L', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-987', concepto: 'Pintura epóxica', alias: 'Epóxica gris', tipo: 'Mantenimiento', esComun: false, categoria: 'Líquido', almacen: 'Dormitorios', ubicacion: 'Estante 1', existencia: 8, unidadBase: 'L', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-124', concepto: 'Limpiador aromático', alias: 'Fabuloso', tipo: 'Servicios Generales', esComun: true, categoria: 'Líquido', almacen: 'Servicios Generales', ubicacion: 'Estante 1', existencia: 12, unidadBase: 'galones', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-125', concepto: 'Cloro', alias: 'Hipoclorito', tipo: 'Servicios Generales', esComun: true, categoria: 'Líquido', almacen: 'Dormitorios', ubicacion: '-', existencia: 18, unidadBase: 'L', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-130', concepto: 'Guantes de látex', alias: 'Guantes', tipo: 'Mantenimiento', esComun: true, categoria: 'Pieza', almacen: 'Mantenimiento', ubicacion: 'Estante 3', existencia: 4, unidadBase: 'piezas', unidades: ['Piezas', 'Cajas']),
    MaterialCatalogo(codigo: 'CD-126', concepto: 'Jabón líquido', alias: 'Jabón manos', tipo: 'Servicios Generales', esComun: true, categoria: 'Líquido', almacen: 'Dormitorios', ubicacion: 'Estante 1', existencia: 8, unidadBase: 'L', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-127', concepto: 'Desengrasante', alias: 'Industrial', tipo: 'Mantenimiento', esComun: false, categoria: 'Líquido', almacen: 'Mantenimiento', ubicacion: 'Estante 4', existencia: 20, unidadBase: 'L', unidades: _litros),
    MaterialCatalogo(codigo: 'CD-131', concepto: 'Escoba industrial', alias: 'Escoba', tipo: 'Servicios Generales', esComun: true, categoria: 'Pieza', almacen: 'Servicios Generales', ubicacion: 'Estante 5', existencia: 15, unidadBase: 'piezas', unidades: ['Piezas', 'Cajas']),
    MaterialCatalogo(codigo: 'CD-132', concepto: 'Trapeador', alias: 'Mechudo', tipo: 'Servicios Generales', esComun: false, categoria: 'Pieza', almacen: 'Servicios Generales', ubicacion: 'Estante 5', existencia: 10, unidadBase: 'piezas', unidades: ['Piezas', 'Cajas']),
  ];

  static const _activos = [
    ActivoCatalogo(codigo: '912391', equipo: 'Rotomartillo SDS Plus', modelo: 'Bosch GBH 2-28', serie: 'KRC-112233445', almacen: 'Mantenimiento', ubicacion: 'Estante 2, Fila 3'),
    ActivoCatalogo(codigo: '912400', equipo: 'Taladro percutor', modelo: 'DeWalt DWD024', serie: 'DW-998877', almacen: 'Mantenimiento', ubicacion: 'Estante 2, Fila 4'),
  ];

  Future<void> _espera() => Future<void>.delayed(const Duration(milliseconds: 250));

  Pagina<T> _paginar<T>(List<T> todos, int pagina, int porPagina) {
    final inicio = (pagina - 1) * porPagina;
    final items = inicio >= todos.length ? <T>[] : todos.skip(inicio).take(porPagina).toList();
    return Pagina(items: items, total: todos.length, pagina: pagina, porPagina: porPagina);
  }

  @override
  Future<Pagina<Solicitante>> buscarSolicitantes(String consulta, {int pagina = 1, int porPagina = 5}) async {
    await _espera();
    final q = consulta.trim().toLowerCase();
    final todos = _solicitantes.where((s) => s.nombre.toLowerCase().contains(q)).toList();
    return _paginar(todos, pagina, porPagina);
  }

  @override
  Future<List<Autorizador>> listarAutorizadores() async {
    await _espera();
    return _autorizadores;
  }

  @override
  Future<OpcionesFiltros> opcionesFiltros() async {
    await _espera();
    List<String> unicos(String Function(MaterialCatalogo) f) => (_materiales.map(f).toSet().toList()..sort());
    return OpcionesFiltros(
      categorias: unicos((m) => m.categoria),
      tipos: unicos((m) => m.tipo),
      almacenes: unicos((m) => m.almacen),
    );
  }

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
    await _espera();
    final q = consulta.trim().toLowerCase();
    final todos = _materiales
        .where((m) =>
            (categoria == null || m.categoria == categoria) &&
            (tipo == null || m.tipo == tipo) &&
            (almacen == null || m.almacen == almacen) &&
            (!soloComunes || m.esComun) &&
            (m.codigo.toLowerCase().contains(q) ||
                m.concepto.toLowerCase().contains(q) ||
                m.alias.toLowerCase().contains(q)))
        .toList();
    return _paginar(todos, pagina, porPagina);
  }

  @override
  Future<List<ActivoCatalogo>> buscarActivos(String consulta) async {
    await _espera();
    final q = consulta.trim().toLowerCase();
    return _activos
        .where((a) => a.equipo.toLowerCase().contains(q) || a.codigo.contains(q) || a.serie.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<AlertaRestriccion?> validarMaterial({
    Solicitante? solicitante,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    await _espera();
    final pedido = '${formatearCantidad(cantidad)} $unidad';
    switch (material.alias) {
      case 'Pinol': // Escenario 8
        return const AlertaRestriccion(
          tipo: TipoAlerta.periodicidad,
          titulo: 'Periodicidad no cumplida',
          regla: '1 medio litro cada 3 días',
          ultimaEntrega: '08:57 a.m. 17/10/2026',
          proximaEntrega: '20/10/2026',
          diasFaltantes: 2,
        );
      case 'Fabuloso': // Escenario 10
        return AlertaRestriccion(
          tipo: TipoAlerta.limiteZona,
          titulo: 'Límite de la zona',
          regla: 'Máximo 3 galones por semana',
          entregado: '1 galón',
          solicitado: pedido,
        );
      default: // Escenario 9: sin restricción
        return null;
    }
  }

  @override
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega s) async {
    await _espera();
    for (final m in s.materiales) {
      if (m.cantidad > m.material.existencia) {
        throw ErrorNegocio('STOCK_INSUFICIENTE', 'Existencia insuficiente.', datos: {
          'codigo': m.material.codigo,
          'nombre': m.material.alias,
          'solicitado': m.cantidad,
          'disponible': m.material.existencia,
          'unidad': m.material.unidadBase,
        });
      }
    }
    _folio++;
    final solicitante = _solicitantes.where((x) => x.id == s.solicitanteId);
    return ResumenEntrega(
      folio: 'ENT-2026-${_folio.toString().padLeft(4, '0')}',
      recibidoPor: solicitante.isNotEmpty ? solicitante.first.nombre : (s.nombreSinRegistro ?? ''),
      area: solicitante.isNotEmpty ? solicitante.first.dependencia : (s.unidadSinRegistro ?? ''),
      fechaHora: '17/10/2026  08:57 a.m.',
      entregadoPor: 'Alicia Beltrán',
      materiales: s.materiales.map((m) => LineaResumen(m.material.codigo, m.material.alias, m.cantidadTexto)).toList(),
      activos: s.activos.map((a) => LineaResumen(a.activo.codigo, a.activo.equipo, a.activo.modelo, a.activo.serie)).toList(),
    );
  }
}
