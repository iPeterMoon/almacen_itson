import 'dart:convert';
import 'dart:typed_data';

/// Modelos de la HU6. SUPUESTO: reflejan los DTO del servidor; ajustar nombres de
/// campos cuando exista el contrato OpenAPI (/docs).

String formatearCantidad(double c) => c % 1 == 0 ? c.toInt().toString() : c.toString();

class Solicitante {
  const Solicitante({
    required this.id,
    required this.nombre,
    required this.dependencia,
    required this.tipo,
    required this.zona,
    this.areaTrabajo,
    this.areaTrabajo2,
  });

  final String id;
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

class Autorizador {
  const Autorizador({required this.id, required this.nombre});
  final String id;
  final String nombre;

  factory Autorizador.fromJson(Map<String, dynamic> j) =>
      Autorizador(id: j['id'] as String, nombre: j['nombre'] as String);
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
  });

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

class ActivoCatalogo {
  const ActivoCatalogo({
    required this.codigo,
    required this.equipo,
    required this.modelo,
    required this.serie,
    required this.almacen,
    required this.ubicacion,
  });

  final String codigo;
  final String equipo;
  final String modelo;
  final String serie;
  final String almacen;
  final String ubicacion;
}

class Autorizacion {
  const Autorizacion({
    required this.autorizadorId,
    required this.autorizadorNombre,
    required this.motivo,
    this.detalleOtro,
  });

  final String autorizadorId;
  final String autorizadorNombre;
  final String motivo;
  final String? detalleOtro;

  Map<String, dynamic> toJson() => {
        'autorizadorId': autorizadorId,
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
    this.autorizacion,
  });

  final MaterialCatalogo material;
  final double cantidad;
  final String unidad;
  final bool entregado;
  final String? comentario;
  final Autorizacion? autorizacion;

  String get cantidadTexto => '${formatearCantidad(cantidad)} $unidad';

  ItemMaterial copyWith({double? cantidad, String? unidad, bool? entregado, String? comentario}) =>
      ItemMaterial(
        material: material,
        cantidad: cantidad ?? this.cantidad,
        unidad: unidad ?? this.unidad,
        entregado: entregado ?? this.entregado,
        comentario: comentario ?? this.comentario,
        autorizacion: autorizacion,
      );

  Map<String, dynamic> toJson() => {
        'codigo': material.codigo,
        'cantidad': cantidad,
        'unidad': unidad,
        if (comentario != null && comentario!.isNotEmpty) 'comentario': comentario,
        if (autorizacion != null) 'autorizacion': autorizacion!.toJson(),
      };
}

class ItemActivo {
  const ItemActivo({
    required this.activo,
    this.dias = 1,
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
    this.nombreSinRegistro,
    this.unidadSinRegistro,
    this.autorizoId,
    this.numeroSolicitud,
    required this.materiales,
    required this.activos,
    required this.firmaEntrega,
    required this.firmaRecibe,
  });

  final String? solicitanteId;
  final String? nombreSinRegistro;
  final String? unidadSinRegistro;
  final String? autorizoId;
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
        if (autorizoId != null) 'autorizoId': autorizoId,
        if (numeroSolicitud != null && numeroSolicitud!.isNotEmpty)
          'numeroSolicitud': numeroSolicitud,
        'materiales': materiales.map((m) => m.toJson()).toList(),
        'activos': activos.map((a) => a.toJson()).toList(),
        'firmaEntregaBase64': base64Encode(firmaEntrega),
        'firmaRecibeBase64': base64Encode(firmaRecibe),
      };
}

class LineaResumen {
  const LineaResumen(this.codigo, this.nombre, this.detalle, [this.extra = '']);
  final String codigo;
  final String nombre;
  final String detalle; // cantidad (materiales) o modelo (activos)
  final String extra; // número de serie (activos)
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
    required this.activos,
  });

  final String folio;
  final String recibidoPor;
  final String area;
  final String fechaHora;
  final String entregadoPor;
  final List<LineaResumen> materiales;
  final List<LineaResumen> activos;
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
