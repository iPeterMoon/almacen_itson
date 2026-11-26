import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/historial_entregas_repositorio.dart';
import '../datos/modelos.dart';
import '../datos/ventanilla_repositorio_api.dart' show minimoCaracteresBusqueda;
import 'entrega_controlador.dart';

/// HU11: página actual del historial de entregas, búsqueda por solicitante/folio
/// y rango de fechas de entrega. Empieza en la página 1 y vuelve a ella al buscar,
/// al filtrar por fechas y cada vez que se termina una entrega.
class HistorialEntregasControlador extends AsyncNotifier<Pagina<EntregaHistorial>> {
  /// Filas por página: las que muestra el Figma.
  static const porPagina = 9;

  int _pagina = 1;
  String _consulta = '';
  DateTime? _desde;
  DateTime? _hasta;
  // Número de la última petición: las respuestas de peticiones anteriores se descartan.
  int _peticion = 0;

  /// Texto de búsqueda (solicitante o folio) con el que se pidió la página actual.
  String get consulta => _consulta;

  DateTime? get desde => _desde;
  DateTime? get hasta => _hasta;
  bool get hayFechas => _desde != null || _hasta != null;

  /// true si la página actual está filtrada. Con menos de [minimoCaracteresBusqueda]
  /// caracteres no se filtra (el servidor no lo acepta) y se ve el historial completo.
  bool get buscando => _consulta.length >= minimoCaracteresBusqueda;

  HistorialEntregasRepositorio get _repo => ref.read(proveedorHistorialEntregasRepositorio);

  /// Sin hora: el API compara días completos de Hermosillo.
  static DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

  @override
  Future<Pagina<EntregaHistorial>> build() {
    // Al terminar una entrega este valor cambia y Riverpod vuelve a ejecutar build().
    // Los filtros se conservan: siguen escritos en la pantalla.
    ref.watch(entregasTerminadasProvider);
    _pagina = 1;
    _peticion++;
    return _repo.listar(
      pagina: 1,
      porPagina: porPagina,
      consulta: _consulta,
      desde: _desde,
      hasta: _hasta,
    );
  }

  /// Filtra por solicitante o folio y vuelve a la página 1. Texto vacío: historial completo.
  Future<void> buscar(String texto) {
    _consulta = texto.trim();
    return irAPagina(1);
  }

  /// Rango inclusivo de fechas de entrega. Con [hasta] null el filtro queda abierto
  /// desde ese día (para poder elegir el segundo extremo después). Si el orden está
  /// invertido, se normaliza para que el API no responda 400.
  Future<void> filtrarPorFechas(DateTime desde, {DateTime? hasta}) {
    var inicio = _dia(desde);
    var fin = hasta == null ? null : _dia(hasta);
    if (fin != null && fin.isBefore(inicio)) {
      final aux = inicio;
      inicio = fin;
      fin = aux;
    }
    _desde = inicio;
    _hasta = fin;
    return irAPagina(1);
  }

  /// Quita el rango de fechas y vuelve a la página 1.
  Future<void> limpiarFechas() {
    _desde = null;
    _hasta = null;
    return irAPagina(1);
  }

  Future<void> irAPagina(int pagina) async {
    _pagina = pagina;
    final peticion = ++_peticion;
    state = const AsyncLoading();
    final resultado = await AsyncValue.guard(() => _repo.listar(
          pagina: pagina,
          porPagina: porPagina,
          consulta: _consulta,
          desde: _desde,
          hasta: _hasta,
        ));
    // Si mientras tanto se pidió otra página u otro filtro, esta respuesta ya no sirve.
    if (peticion == _peticion) state = resultado;
  }

  /// Vuelve a pedir la página actual (botón "Reintentar").
  Future<void> recargar() => irAPagina(_pagina);
}

final historialEntregasProvider =
    AsyncNotifierProvider<HistorialEntregasControlador, Pagina<EntregaHistorial>>(
        HistorialEntregasControlador.new);
