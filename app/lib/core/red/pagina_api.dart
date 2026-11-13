// Página de resultados de una lista del servidor: { datos, total, pagina, limite }.
// [total] es cuántos registros cumplen la búsqueda en todas las páginas.
class PaginaApi<T> {
  const PaginaApi({required this.datos, required this.total, required this.pagina, required this.limite});
  final List<T> datos;
  final int total;
  final int pagina;
  final int limite;

  factory PaginaApi.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) leer) {
    final datos = [for (final f in json['datos'] as List<dynamic>) leer(f as Map<String, dynamic>)];
    return PaginaApi(
      datos: datos,
      total: (json['total'] as num?)?.toInt() ?? datos.length,
      pagina: (json['pagina'] as num?)?.toInt() ?? 1,
      limite: (json['limite'] as num?)?.toInt() ?? datos.length,
    );
  }
}
