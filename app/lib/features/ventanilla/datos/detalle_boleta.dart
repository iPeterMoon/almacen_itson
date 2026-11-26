// Detalle de una boleta para el historial (HU11). Refleja GET /boletas/:id/detalle:
// { id, folio, campusId, campus, entregadoEn, entregadoPor,
//   solicitante: { nombre, dependencia, unidad }, autorizoNombre,
//   materiales: [{ codigo, concepto, almacen, presentacion, cantidad }],
//   herramientas: [{ codigo, nombre, modelo, numeroSerie, estado }] }
import 'modelos.dart' show formatearCantidad;

class DetalleBoleta {
  const DetalleBoleta({
    required this.id,
    required this.folio,
    required this.solicitante,
    this.dependencia,
    this.unidad,
    this.campus,
    this.entregadoEn,
    this.entregadoPor,
    this.autorizoNombre,
    this.materiales = const [],
    this.herramientas = const [],
  });

  final int id;
  final String folio;
  final String solicitante;
  final String? dependencia;
  final String? unidad;
  final String? campus;
  final String? entregadoEn; // ISO 8601
  final String? entregadoPor; // nombre del almacenista
  // Quién autorizó; null si la entrega no lo requirió. El sistema solo guarda el nombre.
  final String? autorizoNombre;
  final List<MaterialDeBoleta> materiales;
  final List<HerramientaDeBoleta> herramientas;

  bool get requirioAutorizacion => autorizoNombre != null && autorizoNombre!.trim().isNotEmpty;

  factory DetalleBoleta.fromJson(Map<String, dynamic> json) {
    final solicitante = json['solicitante'] as Map<String, dynamic>? ?? const {};
    return DetalleBoleta(
      id: (json['id'] as num).toInt(),
      folio: json['folio'] as String,
      solicitante: solicitante['nombre'] as String? ?? '',
      dependencia: solicitante['dependencia'] as String?,
      unidad: solicitante['unidad'] as String?,
      campus: json['campus'] as String?,
      entregadoEn: json['entregadoEn'] as String?,
      entregadoPor: json['entregadoPor'] as String?,
      autorizoNombre: json['autorizoNombre'] as String?,
      materiales: [
        for (final m in (json['materiales'] as List?) ?? const [])
          MaterialDeBoleta.fromJson(m as Map<String, dynamic>),
      ],
      herramientas: [
        for (final h in (json['herramientas'] as List?) ?? const [])
          HerramientaDeBoleta.fromJson(h as Map<String, dynamic>),
      ],
    );
  }
}

class MaterialDeBoleta {
  const MaterialDeBoleta({
    required this.codigo,
    required this.concepto,
    required this.cantidad,
    this.almacen,
    this.presentacion,
  });

  final String codigo;
  final String concepto;
  // Almacén del que se descontó; si salió de varios, el servidor los manda separados por coma.
  final String? almacen;
  final String? presentacion; // "L", "Caja", ...
  final double cantidad;

  /// "10 L", "0.5 L" o solo "3" si no hay presentación.
  String get cantidadTexto {
    final p = presentacion?.trim() ?? '';
    return p.isEmpty ? formatearCantidad(cantidad) : '${formatearCantidad(cantidad)} $p';
  }

  factory MaterialDeBoleta.fromJson(Map<String, dynamic> json) => MaterialDeBoleta(
        codigo: json['codigo'] as String? ?? '',
        concepto: json['concepto'] as String? ?? '',
        almacen: json['almacen'] as String?,
        presentacion: json['presentacion'] as String?,
        cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      );
}

class HerramientaDeBoleta {
  const HerramientaDeBoleta({
    required this.codigo,
    required this.nombre,
    required this.estado,
    this.modelo,
    this.numeroSerie,
  });

  final String codigo;
  final String nombre;
  final String? modelo;
  final String? numeroSerie;
  final String estado; // estado ACTUAL del activo (DISPONIBLE, EN_PRESTAMO, ...)

  factory HerramientaDeBoleta.fromJson(Map<String, dynamic> json) => HerramientaDeBoleta(
        codigo: json['codigo'] as String? ?? '',
        nombre: json['nombre'] as String? ?? '',
        modelo: json['modelo'] as String?,
        numeroSerie: json['numeroSerie'] as String?,
        estado: json['estado'] as String? ?? '',
      );
}
