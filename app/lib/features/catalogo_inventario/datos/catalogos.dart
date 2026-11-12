// Catálogos para los filtros de materiales (HU6, AI-62), tal como los devuelve el
// servidor en GET /catalogo/categorias y GET /catalogo/almacenes.

class Categoria {
  const Categoria({required this.id, required this.nombre});

  final int id;
  final String nombre;

  factory Categoria.fromJson(Map<String, dynamic> json) =>
      Categoria(id: json['id'] as int, nombre: json['nombre'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre};
}

// Almacén de uno de los campus del usuario. [campus] sirve para distinguir almacenes
// con el mismo nombre cuando un supervisor jefe ve varios campus.
class Almacen {
  const Almacen({
    required this.id,
    required this.nombre,
    required this.campusId,
    required this.campus,
  });

  final int id;
  final String nombre;
  final int campusId;
  final String campus;

  factory Almacen.fromJson(Map<String, dynamic> json) => Almacen(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        campusId: json['campusId'] as int,
        campus: json['campus'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'campusId': campusId,
        'campus': campus,
      };
}

// Tipo de producto para el filtro "Tipo". No viene del servidor: son valores fijos
// de la base. "AMBOS" no se ofrece porque el servidor ya lo incluye en los dos.
class TipoProducto {
  const TipoProducto(this.codigo, this.etiqueta);

  // Valor que espera la API en el parámetro "tipo".
  final String codigo;
  // Texto que ve el usuario.
  final String etiqueta;
}

const tiposProducto = [
  TipoProducto('SERVICIOS_GENERALES', 'Servicios Generales'),
  TipoProducto('MANTENIMIENTO', 'Mantenimiento'),
];
