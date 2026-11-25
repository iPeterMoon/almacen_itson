import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/historial_entregas_repositorio.dart';
import '../datos/modelos.dart';
import 'entrega_controlador.dart';

/// HU11: página actual del historial de entregas.
/// Empieza en la página 1 y vuelve a ella cada vez que se termina una entrega,
/// para que la boleta recién creada (la más reciente) aparezca arriba.
class HistorialEntregasControlador extends AsyncNotifier<Pagina<EntregaHistorial>> {
  /// Filas por página: las que muestra el Figma.
  static const porPagina = 9;

  int _pagina = 1;

  HistorialEntregasRepositorio get _repo => ref.read(proveedorHistorialEntregasRepositorio);

  @override
  Future<Pagina<EntregaHistorial>> build() {
    // Al terminar una entrega este valor cambia y Riverpod vuelve a ejecutar build().
    ref.watch(entregasTerminadasProvider);
    _pagina = 1;
    return _repo.listar(pagina: 1, porPagina: porPagina);
  }

  Future<void> irAPagina(int pagina) async {
    _pagina = pagina;
    state = const AsyncLoading();
    final resultado = await AsyncValue.guard(() => _repo.listar(pagina: pagina, porPagina: porPagina));
    // Si se pidió otra página mientras esta cargaba, se descarta la respuesta vieja.
    if (_pagina == pagina) state = resultado;
  }

  /// Vuelve a pedir la página actual (botón "Reintentar").
  Future<void> recargar() => irAPagina(_pagina);
}

final historialEntregasProvider =
    AsyncNotifierProvider<HistorialEntregasControlador, Pagina<EntregaHistorial>>(
        HistorialEntregasControlador.new);
