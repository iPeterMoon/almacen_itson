import 'dart:convert';
import 'dart:typed_data';

import 'dias_prestamo.dart';

/// Modelos de la HU6. SUPUESTO: reflejan los DTO del servidor; ajustar nombres de
/// campos cuando exista el contrato OpenAPI (/docs).

String formatearCantidad(double c) => c % 1 == 0 ? c.toInt().toString() : c.toString();

// Redondea a 3 decimales, los que acepta el servidor. Sumar doubles deja restos
// (0.1 + 0.2 = 0.30000000000000004) que el servidor rechazaría con un 400.
double redondearCantidad(double c) => (c * 1000).roundToDouble() / 1000;

class Solicitante {
  const Solicitante({
    required this.id,
    required this.nombre,
    required this.dependencia,
    required this.tipo,
    required this.zona,
    this.areaTrabajo,
    this.areaTrabajo2,
    this.zonaId,
  });

  // Id del trabajador en el servidor, como texto (el simulado usa "1", "2"...).
  final String id;
  // Zona de la entrega cuando el trabajador tiene solo una; con varias, la base
  // necesita que se elija y por ahora se deja en null.
  final int? zonaId;
  final String nombre;
  final String dependencia;
  final String tipo;
  final String zona;
  final String? areaTrabajo;
  final String? areaTrabajo2;

  factory Solicitante.fromJson(Map<String, dynamic> j) => Solicitante(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        dependencia: j['dependencia'] as String? ?? '',
        tipo: j['tipo'] as String? ?? '',
        zona: j['zona'] as String? ?? '',
        areaTrabajo: j['areaTrabajo'] as String?,
        areaTrabajo2: j['areaTrabajo2'] as String?,
      );
}

class MaterialCatalogo {
  const MaterialCatalogo({
    required this.codigo,
    required this.concepto,
    required this.alias,
    required this.categoria,
    required this.tipo,
    required this.almacen,
    required this.ubicacion,
    required this.existencia,
    required this.unidadBase,
    required this.unidades,
    this.esComun = false,
    this.productoId,
  });

  // Id del producto en el servidor. Solo lo traen los materiales de la API; el
  // repositorio simulado no lo usa.
  final int? productoId;
  final String codigo;
  final String concepto;
  final String alias;
  final String categoria;
  final String tipo;
  final bool esComun; // para el filtro "Más comunes"
  final String almacen;
  final String ubicacion;
  final double existencia;
  final String unidadBase;
  final List<String> unidades;

  String get existenciaTexto => '${formatearCantidad(existencia)} $unidadBase';

  factory MaterialCatalogo.fromJson(Map<String, dynamic> j) => MaterialCatalogo(
        codigo: j['codigo'] as String,
        concepto: j['concepto'] as String,
        alias: j['alias'] as String? ?? '',
        categoria: j['categoria'] as String? ?? '',
        tipo: j['tipo'] as String? ?? '',
        esComun: j['esComun'] as bool? ?? false,
        almacen: j['almacen'] as String? ?? '',
        ubicacion: j['ubicacion'] as String? ?? '-',
        existencia: (j['existencia'] as num).toDouble(),
        unidadBase: j['unidadBase'] as String? ?? '',
        unidades: (j['unidades'] as List?)?.cast<String>() ?? const [],
      );
}

// Estados de un activo, iguales a los del servidor (GET /activos).
const estadoActivoDisponible = 'DISPONIBLE';
const estadoActivoEnPrestamo = 'EN_PRESTAMO';
const estadoActivoEnReparacion = 'EN_REPARACION';
const estadoActivoRoboExtravio = 'ROBO_EXTRAVIO';
const estadoActivoDeBaja = 'DE_BAJA';

class ActivoCatalogo {
  const ActivoCatalogo({
    required this.codigo,
    required this.equipo,
    required this.modelo,
    required this.serie,
    required this.almacen,
    required this.ubicacion,
    this.activoId,
    this.estado = estadoActivoDisponible,
  });

  // Id del activo en el servidor; el repositorio simulado no lo usa.
  final int? activoId;
  final String codigo;
  final String equipo;
  final String modelo;
  final String serie;
  final String almacen;
  final String ubicacion;
  // Estado tal como lo manda el servidor (ver las constantes estadoActivo...).
  final String estado;

  // Solo un activo disponible se puede prestar (HU8, Escenarios 2 y 3).
  bool get disponible => estado == estadoActivoDisponible;
}

/// Motivo obligatorio cuando un material excede periodicidad o límite de zona.
/// La entrega se registra de inmediato; no hay autorización dentro del sistema.
class MotivoExcepcion {
  const MotivoExcepcion({required this.motivo, this.detalleOtro});

  final String motivo;
  final String? detalleOtro;

  Map<String, dynamic> toJson() => {
        'motivo': motivo,
        if (detalleOtro != null && detalleOtro!.isNotEmpty) 'detalleOtro': detalleOtro,
      };
}

enum TipoAlerta { periodicidad, limiteZona }

/// Alerta que devuelve el servidor al validar un material (Escenarios 8 y 10).
class AlertaRestriccion {
  const AlertaRestriccion({
    required this.tipo,
    required this.titulo,
    required this.regla,
    this.ultimaEntrega,
    this.proximaEntrega,
    this.diasFaltantes,
    this.entregado,
    this.solicitado,
  });

  final TipoAlerta tipo;
  final String titulo;
  final String regla;
  final String? ultimaEntrega;
  final String? proximaEntrega;
  final int? diasFaltantes;
  final String? entregado;
  final String? solicitado;
}

class ItemMaterial {
  const ItemMaterial({
    required this.material,
    required this.cantidad,
    required this.unidad,
    this.entregado = true,
    this.comentario,
    this.motivoExcepcion,
  });

  final MaterialCatalogo material;
  final double cantidad;
  final String unidad;
  final bool entregado;
  final String? comentario;
  final MotivoExcepcion? motivoExcepcion;

  String get cantidadTexto => '${formatearCantidad(cantidad)} $unidad';

  ItemMaterial copyWith({
    double? cantidad,
    String? unidad,
    bool? entregado,
    String? comentario,
    MotivoExcepcion? motivoExcepcion,
  }) =>
      ItemMaterial(
        material: material,
        cantidad: cantidad ?? this.cantidad,
        unidad: unidad ?? this.unidad,
        entregado: entregado ?? this.entregado,
        comentario: comentario ?? this.comentario,
        motivoExcepcion: motivoExcepcion ?? this.motivoExcepcion,
      );

  Map<String, dynamic> toJson() => {
        'codigo': material.codigo,
        'cantidad': cantidad,
        'unidad': unidad,
        if (comentario != null && comentario!.isNotEmpty) 'comentario': comentario,
        if (motivoExcepcion != null) 'motivoExcepcion': motivoExcepcion!.toJson(),
      };
}

class ItemActivo {
  const ItemActivo({
    required this.activo,
    this.dias = diasPrestamoPredeterminado,
    this.entregado = true,
    this.comentario,
  });

  final ActivoCatalogo activo;
  final int dias;
  final bool entregado;
  final String? comentario;

  ItemActivo copyWith({int? dias, bool? entregado, String? comentario}) => ItemActivo(
        activo: activo,
        dias: dias ?? this.dias,
        entregado: entregado ?? this.entregado,
        comentario: comentario ?? this.comentario,
      );

  Map<String, dynamic> toJson() => {
        'codigo': activo.codigo,
        'diasPrestamo': dias,
        if (comentario != null && comentario!.isNotEmpty) 'comentario': comentario,
      };
}

/// Cuerpo de la petición que registra la boleta. Las firmas van en base64 (PNG <= 500 KB).
class SolicitudEntrega {
  const SolicitudEntrega({
    this.solicitanteId,
    this.solicitante,
    this.nombreSinRegistro,
    this.unidadSinRegistro,
    this.autorizoNombre,
    this.numeroSolicitud,
    required this.materiales,
    required this.activos,
    required this.firmaEntrega,
    required this.firmaRecibe,
  });

  final String? solicitanteId;
  // El solicitante registrado completo (nombre y dependencia para el resumen).
  final Solicitante? solicitante;
  final String? nombreSinRegistro;
  final String? unidadSinRegistro;
  // Nombre de quien autorizó (opcional, texto libre; puede no estar registrado).
  final String? autorizoNombre;
  final String? numeroSolicitud;
  final List<ItemMaterial> materiales;
  final List<ItemActivo> activos;
  final Uint8List firmaEntrega;
  final Uint8List firmaRecibe;

  Map<String, dynamic> toJson() => {
        if (solicitanteId != null) 'solicitanteId': solicitanteId,
        if (nombreSinRegistro != null) 'solicitanteNoRegistrado': {
          'nombre': nombreSinRegistro,
          'unidad': unidadSinRegistro,
        },
        if (autorizoNombre != null && autorizoNombre!.isNotEmpty)
          'autorizoNombre': autorizoNombre,
        if (numeroSolicitud != null && numeroSolicitud!.isNotEmpty)
          'numeroSolicitud': numeroSolicitud,
        'materiales': materiales.map((m) => m.toJson()).toList(),
        'activos': activos.map((a) => a.toJson()).toList(),
        'firmaEntregaBase64': base64Encode(firmaEntrega),
        'firmaRecibeBase64': base64Encode(firmaRecibe),
      };
}

class LineaResumen {
  const LineaResumen(this.codigo, this.nombre, this.detalle);
  final String codigo;
  final String nombre;
  final String detalle; // cantidad con su unidad
}

/// Una herramienta prestada en la boleta (HU8). El folio del préstamo (PRE-) y la
/// fecha prevista los genera la base; la app solo los muestra.
class LineaHerramientaResumen {
  const LineaHerramientaResumen({
    required this.codigo,
    required this.nombre,
    required this.modelo,
    required this.serie,
    required this.dias,
    required this.fechaPrevista,
    this.folioPrestamo,
  });

  final String codigo;
  final String nombre;
  final String modelo;
  final String serie;
  final int dias;
  // Fecha prevista de devolución ya formateada (DD/MM/AAAA).
  final String fechaPrevista;
  // null mientras el servidor no lo devuelva en el resumen.
  final String? folioPrestamo;
}

/// Resumen que devuelve el servidor. El folio lo genera el servidor, no la app.
class ResumenEntrega {
  const ResumenEntrega({
    required this.folio,
    required this.recibidoPor,
    required this.area,
    required this.fechaHora,
    required this.entregadoPor,
    required this.materiales,
    this.herramientas = const [],
    this.autorizoNombre,
    this.motivos = const [],
  });

  final String folio; // folio de la boleta (BOL-)
  final String recibidoPor; // también es el resguardante de las herramientas
  final String area;
  final String fechaHora;
  final String entregadoPor;
  final List<LineaResumen> materiales; // se entregan
  final List<LineaHerramientaResumen> herramientas; // se prestan
  final String? autorizoNombre;
  final List<String> motivos;
}

/// Detalle del error STOCK_INSUFICIENTE (Escenario 6).
class StockInsuficiente {
  const StockInsuficiente({
    required this.codigoMaterial,
    required this.nombre,
    required this.solicitado,
    required this.disponible,
    required this.unidad,
  });

  final String codigoMaterial;
  final String nombre;
  final double solicitado;
  final double disponible;
  final String unidad;
}

/// Opciones de los filtros de la pantalla de materiales (vienen del servidor).
class OpcionesFiltros {
  const OpcionesFiltros({required this.categorias, required this.tipos, required this.almacenes});
  final List<String> categorias;
  final List<String> tipos;
  final List<String> almacenes;
}

/// Una página de resultados. SUPUESTO: el servidor acepta ?pagina=&porPagina= y responde { items, total }.
class Pagina<T> {
  const Pagina({required this.items, required this.total, required this.pagina, required this.porPagina});
  final List<T> items;
  final int total; // total de registros que cumplen el filtro (todas las páginas)
  final int pagina; // empieza en 1
  final int porPagina;

  int get totalPaginas => total == 0 ? 1 : (total + porPagina - 1) ~/ porPagina;
}
