import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../catalogo_inventario/datos/producto_resumen.dart';
import '../../catalogo_inventario/datos/productos_repository.dart';

// Reglas de la búsqueda de materiales (HU6, AI-30). Las de longitud son las mismas
// que valida el servidor; aquí solo evitan llamadas que de todos modos fallarían.
const esperaBusqueda = Duration(milliseconds: 300);
const minimoCaracteresBusqueda = 2;
const maximoCaracteresBusqueda = 100;

// En qué momento está la búsqueda. La tabla decide qué dibujar según la fase.
enum FaseBusqueda {
  // Texto vacío o muy corto: todavía no se consulta.
  inactiva,
  // Hay una consulta en curso.
  cargando,
  // La última consulta trajo productos.
  conResultados,
  // La última consulta no trajo nada (HU3 E3).
  sinCoincidencias,
  // La última consulta falló; [EstadoBusquedaMateriales.error] trae el mensaje.
  error,
}

// Estado que consume cualquier tabla de resultados. Mientras [fase] es
// "cargando", [productos] conserva los resultados anteriores para que la tabla
// no parpadee al escribir.
class EstadoBusquedaMateriales {
  const EstadoBusquedaMateriales({
    this.texto = '',
    this.fase = FaseBusqueda.inactiva,
    this.productos = const [],
    this.error,
  });

  final String texto;
  final FaseBusqueda fase;
  final List<ProductoResumen> productos;
  final ErrorNegocio? error;

  bool get cargando => fase == FaseBusqueda.cargando;
}

// Controlador de la búsqueda: recibe lo que el usuario escribe, espera 300 ms
// sin cambios (debounce) y consulta el repositorio. Solo aplica la respuesta de
// la búsqueda más reciente: si llega una respuesta vieja, se ignora.
// No sabe nada de la interfaz, así que lo puede usar cualquier tabla o campo.
class BusquedaMaterialesController extends Notifier<EstadoBusquedaMateriales> {
  Timer? _espera;
  // Identifica cada consulta; una respuesta con un número viejo se descarta.
  int _consultaActual = 0;

  @override
  EstadoBusquedaMateriales build() {
    ref.onDispose(() => _espera?.cancel());
    return const EstadoBusquedaMateriales();
  }

  // Se llama en cada cambio del campo de búsqueda.
  void cambiarTexto(String texto) {
    final limpio = texto.trim();
    _espera?.cancel();

    // Mismo texto que la búsqueda vigente (por ejemplo, solo se agregó un espacio):
    // no se consulta otra vez. Tras un error sí, para que escribir de nuevo reintente.
    final mismaBusqueda = limpio == state.texto &&
        (state.fase == FaseBusqueda.cargando ||
            state.fase == FaseBusqueda.conResultados ||
            state.fase == FaseBusqueda.sinCoincidencias);
    if (mismaBusqueda) return;

    if (limpio.length < minimoCaracteresBusqueda || limpio.length > maximoCaracteresBusqueda) {
      // Invalida cualquier consulta en curso para que su respuesta no se aplique.
      _consultaActual++;
      state = EstadoBusquedaMateriales(texto: limpio);
      return;
    }

    _espera = Timer(esperaBusqueda, () => _buscar(limpio));
  }

  // Repite la última búsqueda de inmediato (por ejemplo, después de un error de red).
  Future<void> reintentar() async {
    _espera?.cancel();
    if (state.texto.length < minimoCaracteresBusqueda) return;
    await _buscar(state.texto);
  }

  // Deja la búsqueda como al inicio.
  void limpiar() {
    _espera?.cancel();
    _consultaActual++;
    state = const EstadoBusquedaMateriales();
  }

  Future<void> _buscar(String texto) async {
    final consulta = ++_consultaActual;
    state = EstadoBusquedaMateriales(
      texto: texto,
      fase: FaseBusqueda.cargando,
      productos: state.productos,
    );

    try {
      final resultado = await ref.read(proveedorProductosRepository).buscar(texto: texto);
      if (!ref.mounted || consulta != _consultaActual) return;
      state = EstadoBusquedaMateriales(
        texto: texto,
        fase: resultado.vacio ? FaseBusqueda.sinCoincidencias : FaseBusqueda.conResultados,
        productos: resultado.datos,
      );
    } on ErrorNegocio catch (error) {
      if (!ref.mounted || consulta != _consultaActual) return;
      state = EstadoBusquedaMateriales(texto: texto, fase: FaseBusqueda.error, error: error);
    }
  }
}

// autoDispose: al salir de la pantalla se cancela la espera y se olvida la búsqueda.
final proveedorBusquedaMateriales =
    NotifierProvider.autoDispose<BusquedaMaterialesController, EstadoBusquedaMateriales>(
  BusquedaMaterialesController.new,
);
