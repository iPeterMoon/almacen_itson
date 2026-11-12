// Dónde está guardado un producto y cuánto hay ahí (columna "Almacén" y campo
// "Ubicación" del Figma). El servidor solo manda ubicaciones con existencia.
class UbicacionProducto {
  const UbicacionProducto({
    required this.campusId,
    required this.almacenId,
    required this.almacen,
    required this.ubicacionId,
    required this.ubicacion,
    required this.cantidad,
  });

  final int campusId;
  final int almacenId;
  final String almacen;
  final int ubicacionId;
  // Descripción opcional dentro del almacén (por ejemplo "E1F1"); puede no tener.
  final String? ubicacion;
  // En la unidad base del producto.
  final double cantidad;

  factory UbicacionProducto.fromJson(Map<String, dynamic> json) {
    return UbicacionProducto(
      campusId: json['campusId'] as int,
      almacenId: json['almacenId'] as int,
      almacen: json['almacen'] as String,
      ubicacionId: json['ubicacionId'] as int,
      ubicacion: json['ubicacion'] as String?,
      cantidad: (json['cantidad'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'campusId': campusId,
        'almacenId': almacenId,
        'almacen': almacen,
        'ubicacionId': ubicacionId,
        'ubicacion': ubicacion,
        'cantidad': cantidad,
      };
}

// Producto tal como lo devuelve GET /catalogo/productos (HU6, AI-30). Refleja la
// respuesta del servidor; la existencia ya viene sumada para los campus del
// usuario y en la unidad base del producto ([unidad]).
class ProductoResumen {
  const ProductoResumen({
    required this.id,
    required this.codigo,
    required this.nombreEstandar,
    required this.alias,
    required this.categoria,
    required this.unidad,
    required this.tipo,
    required this.masComunes,
    required this.existencia,
    required this.ultimaEntrada,
    required this.ultimaSalida,
    this.ubicaciones = const [],
  });

  final int id;
  final String codigo;
  final String nombreEstandar;
  final String? alias;
  final String categoria;
  final String unidad;
  // 'SERVICIOS_GENERALES', 'MANTENIMIENTO' o 'AMBOS'.
  final String tipo;
  final bool masComunes;
  final double existencia;
  // Fechas tal como las manda el servidor (ISO 8601); la app no las recalcula.
  final String? ultimaEntrada;
  final String? ultimaSalida;
  // Ordenadas por almacén, como las manda el servidor.
  final List<UbicacionProducto> ubicaciones;

  // La existencia llega como número entero o decimal según la cantidad. Si la
  // respuesta no trae "ubicaciones", la lista queda vacía.
  factory ProductoResumen.fromJson(Map<String, dynamic> json) {
    return ProductoResumen(
      id: json['id'] as int,
      codigo: json['codigo'] as String,
      nombreEstandar: json['nombreEstandar'] as String,
      alias: json['alias'] as String?,
      categoria: json['categoria'] as String,
      unidad: json['unidad'] as String,
      tipo: json['tipo'] as String,
      masComunes: json['masComunes'] as bool,
      existencia: (json['existencia'] as num).toDouble(),
      ultimaEntrada: json['ultimaEntrada'] as String?,
      ultimaSalida: json['ultimaSalida'] as String?,
      ubicaciones: (json['ubicaciones'] as List<dynamic>? ?? const [])
          .map((fila) => UbicacionProducto.fromJson(fila as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'codigo': codigo,
        'nombreEstandar': nombreEstandar,
        'alias': alias,
        'categoria': categoria,
        'unidad': unidad,
        'tipo': tipo,
        'masComunes': masComunes,
        'existencia': existencia,
        'ultimaEntrada': ultimaEntrada,
        'ultimaSalida': ultimaSalida,
        'ubicaciones': [for (final u in ubicaciones) u.toJson()],
      };
}

// Una página de resultados de la búsqueda. El servidor todavía no manda el total
// de coincidencias; se agregará con la paginación (AI-63).
class ResultadoBusquedaProductos {
  const ResultadoBusquedaProductos({
    required this.datos,
    required this.pagina,
    required this.limite,
  });

  final List<ProductoResumen> datos;
  final int pagina;
  final int limite;

  bool get vacio => datos.isEmpty;

  factory ResultadoBusquedaProductos.fromJson(Map<String, dynamic> json) {
    return ResultadoBusquedaProductos(
      datos: (json['datos'] as List<dynamic>)
          .map((fila) => ProductoResumen.fromJson(fila as Map<String, dynamic>))
          .toList(growable: false),
      pagina: json['pagina'] as int,
      limite: json['limite'] as int,
    );
  }
}
