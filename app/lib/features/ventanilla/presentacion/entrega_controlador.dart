import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../datos/modelos.dart';
import '../datos/ventanilla_repositorio.dart';

const _sin = Object();
const int tamanoMaxFirma = 500 * 1024; // 500 KB, según el contrato de firmas

class EntregaState {
  const EntregaState({
    this.paso = 0,
    this.solicitante,
    this.sinRegistro = false,
    this.nombreSinRegistro = '',
    this.unidadSinRegistro = '',
    this.autorizoId,
    this.numeroSolicitud = '',
    this.materiales = const [],
    this.activos = const [],
    this.firmaEntrega,
    this.firmaRecibe,
    this.enviando = false,
    this.error,
    this.stockInsuficiente,
    this.resumen,
  });

  final int paso; // 0 Solicitante, 1 Materiales, 2 Revisión, 3 Confirmación
  final Solicitante? solicitante;
  final bool sinRegistro;
  final String nombreSinRegistro;
  final String unidadSinRegistro;
  final String? autorizoId;
  final String numeroSolicitud; // opcional (Escenarios 3 y 4)
  final List<ItemMaterial> materiales;
  final List<ItemActivo> activos;
  final Uint8List? firmaEntrega;
  final Uint8List? firmaRecibe;
  final bool enviando;
  final String? error;
  final StockInsuficiente? stockInsuficiente;
  final ResumenEntrega? resumen;

  EntregaState copyWith({
    int? paso,
    Object? solicitante = _sin,
    bool? sinRegistro,
    String? nombreSinRegistro,
    String? unidadSinRegistro,
    Object? autorizoId = _sin,
    String? numeroSolicitud,
    List<ItemMaterial>? materiales,
    List<ItemActivo>? activos,
    Object? firmaEntrega = _sin,
    Object? firmaRecibe = _sin,
    bool? enviando,
    Object? error = _sin,
    Object? stockInsuficiente = _sin,
    Object? resumen = _sin,
  }) {
    return EntregaState(
      paso: paso ?? this.paso,
      solicitante: identical(solicitante, _sin) ? this.solicitante : solicitante as Solicitante?,
      sinRegistro: sinRegistro ?? this.sinRegistro,
      nombreSinRegistro: nombreSinRegistro ?? this.nombreSinRegistro,
      unidadSinRegistro: unidadSinRegistro ?? this.unidadSinRegistro,
      autorizoId: identical(autorizoId, _sin) ? this.autorizoId : autorizoId as String?,
      numeroSolicitud: numeroSolicitud ?? this.numeroSolicitud,
      materiales: materiales ?? this.materiales,
      activos: activos ?? this.activos,
      firmaEntrega: identical(firmaEntrega, _sin) ? this.firmaEntrega : firmaEntrega as Uint8List?,
      firmaRecibe: identical(firmaRecibe, _sin) ? this.firmaRecibe : firmaRecibe as Uint8List?,
      enviando: enviando ?? this.enviando,
      error: identical(error, _sin) ? this.error : error as String?,
      stockInsuficiente: identical(stockInsuficiente, _sin)
          ? this.stockInsuficiente
          : stockInsuficiente as StockInsuficiente?,
      resumen: identical(resumen, _sin) ? this.resumen : resumen as ResumenEntrega?,
    );
  }

  String get recibidoPor => sinRegistro ? nombreSinRegistro.trim() : (solicitante?.nombre ?? '');

  int get totalPartidas => materiales.length + activos.length;

  /// Nombres de quienes autorizaron excepciones (se muestran en "Autorizado por").
  List<String> get autorizadoPor => {
        for (final m in materiales)
          if (m.autorizacion != null) m.autorizacion!.autorizadorNombre,
      }.toList();

  bool puedeAvanzar() => switch (paso) {
        0 => sinRegistro
            ? nombreSinRegistro.trim().isNotEmpty && unidadSinRegistro.trim().isNotEmpty
            : solicitante != null,
        1 => totalPartidas > 0,
        2 => materiales.any((m) => m.entregado) || activos.any((a) => a.entregado),
        _ => false,
      };

  bool get puedeConfirmar => firmaEntrega != null && firmaRecibe != null && !enviando;
}

class EntregaController extends Notifier<EntregaState> {
  VentanillaRepositorio get _repo => ref.read(ventanillaRepositorioProvider);

  @override
  EntregaState build() => const EntregaState();

  void reiniciar() => state = const EntregaState();

  // --- Navegación entre pasos ---
  void avanzar() {
    if (state.paso < 3 && state.puedeAvanzar()) state = state.copyWith(paso: state.paso + 1);
  }

  void retroceder() {
    if (state.paso == 0) return;
    // Al salir de la confirmación se descartan las firmas (el lienzo se vacía).
    state = state.copyWith(
      paso: state.paso - 1,
      firmaEntrega: state.paso == 3 ? null : _sin,
      firmaRecibe: state.paso == 3 ? null : _sin,
      error: null,
    );
  }

  // --- Paso 1: solicitante y datos adicionales ---
  void seleccionarSolicitante(Solicitante s) =>
      state = state.copyWith(solicitante: s, sinRegistro: false);

  void usarSinRegistro(bool valor) => state = state.copyWith(
        sinRegistro: valor,
        solicitante: valor ? null : _sin,
      );

  void setNombreSinRegistro(String v) => state = state.copyWith(nombreSinRegistro: v);
  void setUnidadSinRegistro(String v) => state = state.copyWith(unidadSinRegistro: v);
  void setAutorizo(String? id) => state = state.copyWith(autorizoId: id);
  void setNumeroSolicitud(String v) => state = state.copyWith(numeroSolicitud: v);

  // --- Paso 2: materiales y activos ---

  /// Pide al servidor validar periodicidad y límite de zona. Devuelve la alerta si la hay
  /// (la pantalla pide motivo y autorización); si no, agrega el material directamente.
  Future<AlertaRestriccion?> agregarMaterial({
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    final alerta = await _repo.validarMaterial(
      solicitanteId: state.solicitante?.id,
      material: material,
      cantidad: cantidad,
      unidad: unidad,
    );
    if (alerta != null) return alerta;
    _insertar(ItemMaterial(material: material, cantidad: cantidad, unidad: unidad));
    return null;
  }

  void agregarMaterialAutorizado({
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
    required Autorizacion autorizacion,
  }) =>
      _insertar(ItemMaterial(
          material: material, cantidad: cantidad, unidad: unidad, autorizacion: autorizacion));

  void _insertar(ItemMaterial nuevo) {
    final lista = [...state.materiales];
    final i = lista.indexWhere((m) => m.material.codigo == nuevo.material.codigo);
    if (i >= 0) {
      lista[i] = nuevo;
    } else {
      lista.add(nuevo);
    }
    state = state.copyWith(materiales: lista);
  }

  void quitarMaterial(String codigo) => state = state.copyWith(
      materiales: state.materiales.where((m) => m.material.codigo != codigo).toList());

  void cambiarCantidad(String codigo, double cantidad) {
    if (cantidad <= 0) return;
    state = state.copyWith(
        materiales: [
      for (final m in state.materiales)
        if (m.material.codigo == codigo) m.copyWith(cantidad: cantidad) else m
    ]);
  }

  void cambiarUnidad(String codigo, String unidad) => state = state.copyWith(materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == codigo) m.copyWith(unidad: unidad) else m
      ]);

  void agregarActivo(ActivoCatalogo activo) {
    if (state.activos.any((a) => a.activo.codigo == activo.codigo)) return;
    state = state.copyWith(activos: [...state.activos, ItemActivo(activo: activo)]);
  }

  void quitarActivo(String codigo) => state =
      state.copyWith(activos: state.activos.where((a) => a.activo.codigo != codigo).toList());

  void cambiarDias(String codigo, int dias) {
    if (dias < 1) return;
    state = state.copyWith(activos: [
      for (final a in state.activos)
        if (a.activo.codigo == codigo) a.copyWith(dias: dias) else a
    ]);
  }

  // --- Paso 3: revisión ---
  void marcarMaterial(String codigo, bool v) => state = state.copyWith(materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == codigo) m.copyWith(entregado: v) else m
      ]);

  void marcarActivo(String codigo, bool v) => state = state.copyWith(activos: [
        for (final a in state.activos)
          if (a.activo.codigo == codigo) a.copyWith(entregado: v) else a
      ]);

  void marcarTodo(bool v) => state = state.copyWith(
        materiales: [for (final m in state.materiales) m.copyWith(entregado: v)],
        activos: [for (final a in state.activos) a.copyWith(entregado: v)],
      );

  bool get todoMarcado =>
      state.totalPartidas > 0 &&
      state.materiales.every((m) => m.entregado) &&
      state.activos.every((a) => a.entregado);

  /// Escenario 5: comentario por material (o activo) antes de confirmar.
  void comentarMaterial(String codigo, String texto) => state = state.copyWith(materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == codigo) m.copyWith(comentario: texto.trim()) else m
      ]);

  void comentarActivo(String codigo, String texto) => state = state.copyWith(activos: [
        for (final a in state.activos)
          if (a.activo.codigo == codigo) a.copyWith(comentario: texto.trim()) else a
      ]);

  // --- Paso 4: firmas y confirmación ---
  void setFirmaEntrega(Uint8List? png) => _setFirma(png, entrega: true);
  void setFirmaRecibe(Uint8List? png) => _setFirma(png, entrega: false);

  void _setFirma(Uint8List? png, {required bool entrega}) {
    if (png != null && png.length > tamanoMaxFirma) {
      state = state.copyWith(error: 'La firma es demasiado grande (máximo 500 KB). Intenta de nuevo.');
      return;
    }
    state = entrega
        ? state.copyWith(firmaEntrega: png, error: null)
        : state.copyWith(firmaRecibe: png, error: null);
  }

  Future<void> confirmar() async {
    final fe = state.firmaEntrega;
    final fr = state.firmaRecibe;
    if (fe == null || fr == null) {
      state = state.copyWith(error: 'Se requieren la firma de quien entrega y de quien recibe.');
      return;
    }
    state = state.copyWith(enviando: true, error: null, stockInsuficiente: null);
    try {
      final resumen = await _repo.registrarEntrega(SolicitudEntrega(
        solicitanteId: state.sinRegistro ? null : state.solicitante?.id,
        nombreSinRegistro: state.sinRegistro ? state.nombreSinRegistro.trim() : null,
        unidadSinRegistro: state.sinRegistro ? state.unidadSinRegistro.trim() : null,
        autorizoId: state.autorizoId,
        numeroSolicitud: state.numeroSolicitud.trim().isEmpty ? null : state.numeroSolicitud.trim(),
        materiales: state.materiales.where((m) => m.entregado).toList(),
        activos: state.activos.where((a) => a.entregado).toList(),
        firmaEntrega: fe,
        firmaRecibe: fr,
      ));
      state = state.copyWith(enviando: false, resumen: resumen);
    } on ErrorNegocio catch (e) {
      if (e.codigo == 'STOCK_INSUFICIENTE') {
        // SUPUESTO: el servidor manda en "datos" el material y la existencia disponible.
        state = state.copyWith(
          enviando: false,
          stockInsuficiente: StockInsuficiente(
            codigoMaterial: e.datos['codigo'] as String? ?? '',
            nombre: e.datos['nombre'] as String? ?? '',
            solicitado: (e.datos['solicitado'] as num?)?.toDouble() ?? 0,
            disponible: (e.datos['disponible'] as num?)?.toDouble() ?? 0,
            unidad: e.datos['unidad'] as String? ?? '',
          ),
        );
      } else {
        state = state.copyWith(enviando: false, error: e.mensaje);
      }
    } catch (_) {
      state = state.copyWith(enviando: false, error: 'No se pudo conectar con el servidor.');
    }
  }

  /// Escenario 6: ajusta la cantidad a lo disponible; nunca guarda más que el stock.
  void ajustarAStock() {
    final s = state.stockInsuficiente;
    if (s == null) return;
    state = state.copyWith(
      stockInsuficiente: null,
      materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == s.codigoMaterial) m.copyWith(cantidad: s.disponible) else m
      ],
    );
  }

  void descartarAvisoStock() => state = state.copyWith(stockInsuficiente: null);
  void cerrarResumen() => state = state.copyWith(resumen: null);
}

// ---------------- Proveedores ----------------

final ventanillaRepositorioProvider =
    Provider<VentanillaRepositorio>((ref) => VentanillaRepositorioSimulado());

/// SUPUESTO: el nombre del almacenista sale del perfil de sesión (feature autenticacion).
final almacenistaActualProvider = Provider<String>((ref) => 'Alicia García Beltrán');

final entregaControllerProvider =
    NotifierProvider<EntregaController, EntregaState>(EntregaController.new);

/// Texto de búsqueda simple (Notifier en lugar de StateProvider, compatible con Riverpod 2.x y 3.x).
class ConsultaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String valor) => state = valor;
}

final consultaSolicitantesProvider =
    NotifierProvider<ConsultaNotifier, String>(ConsultaNotifier.new);
final solicitantesProvider = FutureProvider.autoDispose<List<Solicitante>>((ref) {
  final q = ref.watch(consultaSolicitantesProvider);
  return ref.watch(ventanillaRepositorioProvider).buscarSolicitantes(q);
});

final autorizadoresProvider = FutureProvider<List<Autorizador>>(
    (ref) => ref.watch(ventanillaRepositorioProvider).listarAutorizadores());

const _noCambia = Object();

/// Filtros de la pantalla de materiales (búsqueda, categoría, tipo, almacén y "Más comunes").
class FiltroMateriales {
  const FiltroMateriales({
    this.consulta = '',
    this.categoria,
    this.tipo,
    this.almacen,
    this.soloComunes = false,
  });

  final String consulta;
  final String? categoria;
  final String? tipo;
  final String? almacen;
  final bool soloComunes;

  FiltroMateriales copyWith({
    String? consulta,
    Object? categoria = _noCambia,
    Object? tipo = _noCambia,
    Object? almacen = _noCambia,
    bool? soloComunes,
  }) =>
      FiltroMateriales(
        consulta: consulta ?? this.consulta,
        categoria: identical(categoria, _noCambia) ? this.categoria : categoria as String?,
        tipo: identical(tipo, _noCambia) ? this.tipo : tipo as String?,
        almacen: identical(almacen, _noCambia) ? this.almacen : almacen as String?,
        soloComunes: soloComunes ?? this.soloComunes,
      );
}

class FiltroMaterialesNotifier extends Notifier<FiltroMateriales> {
  @override
  FiltroMateriales build() => const FiltroMateriales();

  void setConsulta(String v) => state = state.copyWith(consulta: v);
  void setCategoria(String? v) => state = state.copyWith(categoria: v);
  void setTipo(String? v) => state = state.copyWith(tipo: v);
  void setAlmacen(String? v) => state = state.copyWith(almacen: v);

  /// "Más comunes" (true) o "Todos" (false). "Todos" también limpia los tres filtros.
  void setSoloComunes(bool v) => state = v
      ? state.copyWith(soloComunes: true)
      : state.copyWith(soloComunes: false, categoria: null, tipo: null, almacen: null);
}

final filtroMaterialesProvider =
    NotifierProvider<FiltroMaterialesNotifier, FiltroMateriales>(FiltroMaterialesNotifier.new);

final opcionesFiltrosProvider = FutureProvider<OpcionesFiltros>(
    (ref) => ref.watch(ventanillaRepositorioProvider).opcionesFiltros());

final materialesProvider = FutureProvider.autoDispose<List<MaterialCatalogo>>((ref) {
  final f = ref.watch(filtroMaterialesProvider);
  return ref.watch(ventanillaRepositorioProvider).buscarMateriales(
        consulta: f.consulta,
        categoria: f.categoria,
        tipo: f.tipo,
        almacen: f.almacen,
        soloComunes: f.soloComunes,
      );
});

final consultaActivosProvider =
    NotifierProvider<ConsultaNotifier, String>(ConsultaNotifier.new);
final activosProvider = FutureProvider.autoDispose<List<ActivoCatalogo>>((ref) {
  final q = ref.watch(consultaActivosProvider);
  return ref.watch(ventanillaRepositorioProvider).buscarActivos(q);
});
