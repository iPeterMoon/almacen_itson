import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/historial_entregas_repositorio.dart';
import '../datos/modelos.dart';
import '../datos/ventanilla_repositorio_api.dart' show minimoCaracteresBusqueda;
import 'entrega_controlador.dart';

/// HU11: página actual del historial de entregas y la búsqueda aplicada.
/// Empieza en la página 1 y vuelve a ella al buscar y cada vez que se termina una
/// entrega, para que la boleta recién creada (la más reciente) aparezca arriba.
class HistorialEntregasControlador extends AsyncNotifier<Pagina<EntregaHistorial>> {
  /// Filas por página: las que muestra el Figma.
  static const porPagina = 9;

  int _pagina = 1;
  String _consulta = '';
  // Número de la última petición: las respuestas de peticiones anteriores se descartan.
  int _peticion = 0;

  /// Texto de búsqueda (solicitante o folio) con el que se pidió la página actual.
  String get consulta => _consulta;

  /// true si la página actual está filtrada. Con menos de [minimoCaracteresBusqueda]
  /// caracteres no se filtra (el servidor no lo acepta) y se ve el historial completo.
  bool get buscando => _consulta.length >= minimoCaracteresBusqueda;

  HistorialEntregasRepositorio get _repo => ref.read(proveedorHistorialEntregasRepositorio);

  @override
  Future<Pagina<EntregaHistorial>> build() {
    // Al terminar una entrega este valor cambia y Riverpod vuelve a ejecutar build().
    // La búsqueda se conserva: es la misma que sigue escrita en el campo.
    ref.watch(entregasTerminadasProvider);
    _pagina = 1;
    _peticion++;
    return _repo.listar(pagina: 1, porPagina: porPagina, consulta: _consulta);
  }

  /// Filtra por solicitante o folio y vuelve a la página 1. Texto vacío: historial completo.
  Future<void> buscar(String texto) {
    _consulta = texto.trim();
    return irAPagina(1);
  }

  Future<void> irAPagina(int pagina) async {
    _pagina = pagina;
    final peticion = ++_peticion;
    state = const AsyncLoading();
    final resultado = await AsyncValue.guard(
        () => _repo.listar(pagina: pagina, porPagina: porPagina, consulta: _consulta));
    // Si mientras tanto se pidió otra página u otra búsqueda, esta respuesta ya no sirve.
    if (peticion == _peticion) state = resultado;
  }

  /// Vuelve a pedir la página actual (botón "Reintentar").
  Future<void> recargar() => irAPagina(_pagina);
}

final historialEntregasProvider =
    AsyncNotifierProvider<HistorialEntregasControlador, Pagina<EntregaHistorial>>(
        HistorialEntregasControlador.new);
