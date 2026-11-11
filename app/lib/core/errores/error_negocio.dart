/// Error de negocio que manda el servidor: { "codigo": "...", "mensaje": "..." }.
/// SUPUESTO: el campo opcional "datos" trae detalles (ej. stock disponible).
class ErrorNegocio implements Exception {
  const ErrorNegocio(this.codigo, this.mensaje, {this.datos = const {}});

  final String codigo;
  final String mensaje;
  final Map<String, dynamic> datos;

  factory ErrorNegocio.fromJson(Map<String, dynamic> json) => ErrorNegocio(
        json['codigo'] as String? ?? 'DESCONOCIDO',
        json['mensaje'] as String? ?? 'Ocurrió un error inesperado.',
        datos: (json['datos'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  String toString() => 'ErrorNegocio($codigo): $mensaje';
}
