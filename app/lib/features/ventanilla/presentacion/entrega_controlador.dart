import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/validacion/sin_emojis.dart';
import '../../../core/validacion/limites_texto.dart';
import '../../autenticacion/datos/supervisores_repositorio.dart';
import '../../autenticacion/presentacion/sesion_controlador.dart';
import '../datos/dias_prestamo.dart';
import '../datos/modelos.dart';
import '../datos/ventanilla_repositorio.dart';
import 'avisos_activos.dart';

const _sin = Object();
const int tamanoMaxFirma = 500 * 1024; // 500 KB, según el contrato de firmas

class EntregaState {
  const EntregaState({
    this.paso = 0,
    this.solicitante,
    this.sinRegistro = false,
    this.nombreSinRegistro = '',
    this.unidadSinRegistro = '',
    this.autorizoNombre = '',
    this.numeroSolicitud = '',
    this.materiales = const [],
    this.activos = const [],
    this.firmaEntrega,
    this.firmaRecibe,
    this.enviando = false,
    this.error,
    this.stockInsuficiente,
    this.resumen,
    this.validandoActivo,
    this.solicitanteConVencido = false,
  });

  final int paso; // 0 Solicitante, 1 Materiales, 2 Revisión, 3 Confirmación
  final Solicitante? solicitante;
  final bool sinRegistro;
  final String nombreSinRegistro;
  final String unidadSinRegistro;
  // "Autorizó" es opcional y de texto libre: también vale un supervisor no registrado.
  final String autorizoNombre;
  final String numeroSolicitud; // opcional (Escenarios 3 y 4)
  final List<ItemMaterial> materiales;
  final List<ItemActivo> activos;
  final Uint8List? firmaEntrega;
  final Uint8List? firmaRecibe;
  final bool enviando;
  final String? error;
  final StockInsuficiente? stockInsuficiente;
  final ResumenEntrega? resumen;
  // Código del activo que se está validando con el servidor (para no tocarlo dos veces).
  final String? validandoActivo;
  // HU8 E5: el solicitante actual tiene un préstamo vencido. Solo se avisa.
  final bool solicitanteConVencido;

  EntregaState copyWith({
    int? paso,
    Object? solicitante = _sin,
    bool? sinRegistro,
    String? nombreSinRegistro,
    String? unidadSinRegistro,
    String? autorizoNombre,
    String? numeroSolicitud,
    List<ItemMaterial>? materiales,
    List<ItemActivo>? activos,
    Object? firmaEntrega = _sin,
    Object? firmaRecibe = _sin,
    bool? enviando,
    Object? error = _sin,
    Object? stockInsuficiente = _sin,
    Object? resumen = _sin,
    Object? validandoActivo = _sin,
    bool? solicitanteConVencido,
  }) {
    return EntregaState(
      paso: paso ?? this.paso,
      solicitante: identical(solicitante, _sin) ? this.solicitante : solicitante as Solicitante?,
      sinRegistro: sinRegistro ?? this.sinRegistro,
      nombreSinRegistro: nombreSinRegistro ?? this.nombreSinRegistro,
      unidadSinRegistro: unidadSinRegistro ?? this.unidadSinRegistro,
      autorizoNombre: autorizoNombre ?? this.autorizoNombre,
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
      validandoActivo:
          identical(validandoActivo, _sin) ? this.validandoActivo : validandoActivo as String?,
      solicitanteConVencido: solicitanteConVencido ?? this.solicitanteConVencido,
    );
  }

  String get recibidoPor => sinRegistro ? nombreSinRegistro.trim() : (solicitante?.nombre ?? '');

  int get totalPartidas => materiales.length + activos.length;

  /// Alguna herramienta quedó con los días vacíos o en 0.
  bool get hayDiasInvalidos => activos.any((a) => !diasPrestamoValidos(a.dias));

  /// Nombres de quienes autorizaron excepciones (se muestran en "Autorizado por").
  List<String> get autorizadoPor =>
      autorizoNombre.trim().isEmpty ? const [] : [autorizoNombre.trim()];

  bool puedeAvanzar() => switch (paso) {
        0 => sinRegistro
            ? nombreSinRegistro.trim().isNotEmpty && unidadSinRegistro.trim().isNotEmpty
            : solicitante != null,
        // HU8: toda herramienta necesita al menos 1 día de préstamo.
        1 => totalPartidas > 0 && !hayDiasInvalidos,
        2 => materiales.any((m) => m.entregado) || activos.any((a) => a.entregado),
        _ => false,
      };

  bool get puedeConfirmar => firmaEntrega != null && firmaRecibe != null && !enviando;
}

class EntregaController extends Notifier<EntregaState> {
  VentanillaRepositorio get _repo => ref.read(ventanillaRepositorioProvider);

  @override
  EntregaState build() => const EntregaState();

  void reiniciar() {
    state = const EntregaState();
    _limpiarBusquedas();
  }

  // Los textos de búsqueda viven en providers que sobreviven al cambio de paso, pero
  // los campos de texto se crean vacíos al volver. Si no se limpian, la tabla queda
  // filtrada con la barra en blanco. Se limpian al salir de un paso y al empezar
  // una boleta. (Los filtros de categoría, tipo y almacén sí se ven en pantalla y se conservan.)
  void _limpiarBusquedas() {
    if (ref.read(consultaSolicitantesProvider).isNotEmpty) {
      ref.read(consultaSolicitantesProvider.notifier).set('');
    }
    if (ref.read(consultaActivosProvider).isNotEmpty) {
      ref.read(consultaActivosProvider.notifier).set('');
    }
    if (ref.read(filtroMaterialesProvider).consulta.isNotEmpty) {
      ref.read(filtroMaterialesProvider.notifier).setConsulta('');
    }
  }

  // --- Navegación entre pasos ---
  void avanzar() {
    if (state.paso < 3 && state.puedeAvanzar()) {
      state = state.copyWith(paso: state.paso + 1);
      _limpiarBusquedas();
    }
  }

  void retroceder() {
    if (state.paso == 0) return;
    _limpiarBusquedas();
    // Al salir de la confirmación se descartan las firmas (el lienzo se vacía).
    state = state.copyWith(
      paso: state.paso - 1,
      firmaEntrega: state.paso == 3 ? null : _sin,
      firmaRecibe: state.paso == 3 ? null : _sin,
      error: null,
    );
  }

  // --- Paso 1: solicitante y datos adicionales ---
  // Cambiar de solicitante quita el aviso de vencido: era del anterior.
  void seleccionarSolicitante(Solicitante s) => state =
      state.copyWith(solicitante: s, sinRegistro: false, solicitanteConVencido: false);

  /// Permite quitar la selección para elegir a otro trabajador (o a ninguno).
  void deseleccionarSolicitante() =>
      state = state.copyWith(solicitante: null, solicitanteConVencido: false);

  void usarSinRegistro(bool valor) => state = state.copyWith(
        sinRegistro: valor,
        solicitante: valor ? null : _sin,
        solicitanteConVencido: false,
      );

  void setNombreSinRegistro(String v) =>
      state = state.copyWith(nombreSinRegistro: quitarEmojis(v));
  void setUnidadSinRegistro(String v) =>
      state = state.copyWith(unidadSinRegistro: quitarEmojis(v));

  /// Texto libre, opcional. Se limita a 200 caracteres como la columna de la boleta.
  void setAutorizoNombre(String valor) {
    final limpio = quitarEmojis(valor).trim();
    final texto = limpio.length > limiteNombre ? limpio.substring(0, limiteNombre) : limpio;
    state = state.copyWith(autorizoNombre: texto);
  }

  void setNumeroSolicitud(String v) => state = state.copyWith(numeroSolicitud: quitarEmojis(v));

  // --- Paso 2: materiales y activos ---

  /// Pide al servidor validar periodicidad y límite de zona. Devuelve la alerta si la hay
  /// (la pantalla sugiere pedir autorización y exige el motivo); si no, agrega el material directamente.
  Future<AlertaRestriccion?> agregarMaterial({
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    final existente = _buscarMaterial(material.codigo);
    if (existente != null && existente.unidad != unidad) {
      // No hay conversión de unidades en la app: solo se suma si la unidad es la misma.
      throw ErrorNegocio(
        'UNIDAD_DISTINTA',
        'Este material ya está en la boleta en "${existente.unidad}". '
        'Usa la misma unidad para sumar la cantidad, o cámbiala en "Materiales a entregar".',
      );
    }
    // La periodicidad y el límite de zona se validan con el total que quedaría en la boleta.
    final alerta = await _repo.validarMaterial(
      solicitante: state.sinRegistro ? null : state.solicitante,
      material: material,
      cantidad: redondearCantidad((existente?.cantidad ?? 0) + cantidad),
      unidad: unidad,
    );
    if (alerta != null) return alerta;
    _insertar(ItemMaterial(material: material, cantidad: cantidad, unidad: unidad));
    return null;
  }

  void agregarMaterialConMotivo({
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
    required MotivoExcepcion motivoExcepcion,
  }) =>
      _insertar(ItemMaterial(
          material: material, cantidad: cantidad, unidad: unidad, motivoExcepcion: motivoExcepcion));

  ItemMaterial? _buscarMaterial(String codigo) {
    for (final m in state.materiales) {
      if (m.material.codigo == codigo) return m;
    }
    return null;
  }

  /// Si el material ya está en la boleta (misma unidad) se SUMA la cantidad; no se reemplaza.
  void _insertar(ItemMaterial nuevo) {
    final lista = [...state.materiales];
    final i = lista.indexWhere((m) => m.material.codigo == nuevo.material.codigo);
    if (i >= 0) {
      final ex = lista[i];
      lista[i] = ItemMaterial(
        material: ex.material,
        cantidad: redondearCantidad(ex.cantidad + nuevo.cantidad),
        unidad: ex.unidad,
        entregado: ex.entregado,
        comentario: ex.comentario,
        motivoExcepcion: nuevo.motivoExcepcion ?? ex.motivoExcepcion,
      );
    } else {
      lista.add(nuevo);
    }
    state = state.copyWith(materiales: lista);
  }

  void quitarMaterial(String codigo) => state = state.copyWith(
      materiales: state.materiales.where((m) => m.material.codigo != codigo).toList());

  /// Cambia la cantidad de un material de la boleta. Si sube y el material no tiene
  /// motivo de excepción, la valida antes en el servidor: si rompe la periodicidad o
  /// el límite de la zona devuelve la alerta y no cambia nada (la pantalla pide el
  /// motivo y llama a [cambiarCantidadConMotivo]). Si no hay existencia lanza
  /// STOCK_INSUFICIENTE. Bajar la cantidad no puede romper ninguna regla.
  Future<AlertaRestriccion?> cambiarCantidad(String codigo, double cantidad) async {
    final item = _buscarMaterial(codigo);
    final nueva = redondearCantidad(cantidad);
    if (item == null || nueva <= 0) return null;
    if (nueva > item.cantidad && item.motivoExcepcion == null) {
      final alerta = await _repo.validarMaterial(
        solicitante: state.sinRegistro ? null : state.solicitante,
        material: item.material,
        cantidad: nueva,
        unidad: item.unidad,
      );
      if (alerta != null) return alerta;
    }
    _actualizarMaterial(codigo, (m) => m.copyWith(cantidad: nueva));
    return null;
  }

  void cambiarCantidadConMotivo(String codigo, double cantidad, MotivoExcepcion motivo) =>
      _actualizarMaterial(codigo,
          (m) => m.copyWith(cantidad: redondearCantidad(cantidad), motivoExcepcion: motivo));

  /// Guarda el motivo de la excepción en un material que ya está en la boleta.
  void establecerMotivoExcepcion(String codigo, MotivoExcepcion motivo) =>
      _actualizarMaterial(codigo, (m) => m.copyWith(motivoExcepcion: motivo));

  void _actualizarMaterial(String codigo, ItemMaterial Function(ItemMaterial) cambio) =>
      state = state.copyWith(materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == codigo) cambio(m) else m
      ]);

  /// Vuelve a validar los materiales sin motivo de excepción con el solicitante actual. Se
  /// usa al salir del paso 1 cuando ya hay materiales (se regresó a cambiar el
  /// solicitante): lo que valía para uno puede romper las reglas de otro. Devuelve
  /// los materiales que ahora necesitan autorización. La existencia no se revisa
  /// aquí; la vuelve a validar el servidor al confirmar.
  Future<List<(ItemMaterial, AlertaRestriccion)>> revalidarMateriales() async {
    final solicitante = state.sinRegistro ? null : state.solicitante;
    final pendientes = <(ItemMaterial, AlertaRestriccion)>[];
    for (final m in state.materiales) {
      if (m.motivoExcepcion != null) continue;
      try {
        final alerta = await _repo.validarMaterial(
          solicitante: solicitante,
          material: m.material,
          cantidad: m.cantidad,
          unidad: m.unidad,
        );
        if (alerta != null) pendientes.add((m, alerta));
      } on ErrorNegocio catch (e) {
        if (e.codigo != 'STOCK_INSUFICIENTE') rethrow;
      }
    }
    return pendientes;
  }

  void cambiarUnidad(String codigo, String unidad) => state = state.copyWith(materiales: [
        for (final m in state.materiales)
          if (m.material.codigo == codigo) m.copyWith(unidad: unidad) else m
      ]);

  /// Agrega un equipo a la boleta con 1 día de préstamo. Solo se agregan los
  /// disponibles; el servidor vuelve a validarlo al confirmar (HU8, Escenarios 2 y 3).
  void agregarActivo(ActivoCatalogo activo) {
    if (!activo.disponible) return;
    if (state.activos.any((a) => a.activo.codigo == activo.codigo)) return;
    state = state.copyWith(activos: [...state.activos, ItemActivo(activo: activo)]);
  }

  /// HU8 E2-E5: valida el activo con el servidor antes de agregarlo. Si no se puede
  /// prestar (no disponible o ya prestado) no lo agrega y devuelve la validación para
  /// que la pantalla muestre el aviso. Si el solicitante tiene un préstamo vencido, lo
  /// agrega igual y deja el aviso en [EntregaState.solicitanteConVencido]. Lanza
  /// [ErrorNegocio] con el mensaje ya traducido (ej. "Activo no encontrado").
  Future<ValidacionActivo?> validarYAgregarActivo(ActivoCatalogo activo) async {
    if (state.validandoActivo != null) return null;
    if (state.activos.any((a) => a.activo.codigo == activo.codigo)) return null;
    state = state.copyWith(validandoActivo: activo.codigo);
    try {
      final v = await _repo.validarActivo(
        activo: activo,
        solicitante: state.sinRegistro ? null : state.solicitante,
      );
      if (!v.prestable) return v;
      state = state.copyWith(
        activos: [...state.activos, ItemActivo(activo: v.activo)],
        solicitanteConVencido: state.solicitanteConVencido || v.solicitanteConVencido,
      );
      return v;
    } on ErrorNegocio catch (e) {
      throw ErrorNegocio(e.codigo, mensajeDeError(e), estadoHttp: e.estadoHttp, datos: e.datos);
    } finally {
      state = state.copyWith(validandoActivo: null);
    }
  }

  /// Casilla "Agregar" de la tabla de activos: marca o desmarca el equipo.
  void alternarActivo(ActivoCatalogo activo) {
    if (state.activos.any((a) => a.activo.codigo == activo.codigo)) {
      quitarActivo(activo.codigo);
    } else {
      agregarActivo(activo);
    }
  }

  void quitarActivo(String codigo) => state =
      state.copyWith(activos: state.activos.where((a) => a.activo.codigo != codigo).toList());

  /// Cambia los días de préstamo de una herramienta (entre 0 y [diasPrestamoMaximo]).
  /// 0 se acepta a propósito: es el campo vacío o en cero, y la boleta no avanza
  /// (puedeAvanzar) hasta que se corrija.
  void cambiarDias(String codigo, int dias) {
    final validos = dias < 0 ? 0 : (dias > diasPrestamoMaximo ? diasPrestamoMaximo : dias);
    state = state.copyWith(activos: [
      for (final a in state.activos)
        if (a.activo.codigo == codigo) a.copyWith(dias: validos) else a
    ]);
  }

  /// Lo que se escribe en el campo de días: vacío es 0 y se limita al máximo.
  void escribirDias(String codigo, String texto) => cambiarDias(codigo, diasDeTexto(texto));

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
          if (m.material.codigo == codigo) m.copyWith(comentario: quitarEmojis(texto).trim()) else m
      ]);

  void comentarActivo(String codigo, String texto) => state = state.copyWith(activos: [
        for (final a in state.activos)
          if (a.activo.codigo == codigo) a.copyWith(comentario: quitarEmojis(texto).trim()) else a
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
    final numero = quitarEmojis(state.numeroSolicitud.trim());
    try {
      final resumen = await _repo.registrarEntrega(SolicitudEntrega(
        solicitanteId: state.sinRegistro ? null : state.solicitante?.id,
        solicitante: state.sinRegistro ? null : state.solicitante,
        nombreSinRegistro: state.sinRegistro ? quitarEmojis(state.nombreSinRegistro.trim()) : null,
        unidadSinRegistro: state.sinRegistro ? quitarEmojis(state.unidadSinRegistro.trim()) : null,
        autorizoNombre: state.autorizoNombre.isEmpty ? null : state.autorizoNombre,
        numeroSolicitud: numero.isEmpty ? null : numero,
        materiales: state.materiales.where((m) => m.entregado).toList(),
        activos: state.activos.where((a) => a.entregado).toList(),
        firmaEntrega: fe,
        firmaRecibe: fr,
      ));
      state = state.copyWith(enviando: false, resumen: resumen);
    } on ErrorNegocio catch (e) {
      // El diálogo para ajustar la cantidad necesita saber qué material falló. El
      // servidor real no manda ese detalle (solo el mensaje), así que en ese caso
      // se muestra el mensaje tal cual.
      if (e.codigo == 'STOCK_INSUFICIENTE' && e.datos['codigo'] is String) {
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
        // Los errores de activo (prestado, no disponible, no encontrado) se traducen
        // a los mensajes de la HU8.
        state = state.copyWith(enviando: false, error: mensajeDeError(e));
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

/// Nombre del usuario con sesión iniciada; se muestra como quien entrega.
final almacenistaActualProvider = Provider<String>(
    (ref) => ref.watch(controladorSesionProvider).value?.usuario.nombre ?? '');

/// La hora actual. Se cambia en las pruebas para fijar "hoy" en la fecha prevista de devolución.
final relojProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final entregaControllerProvider =
    NotifierProvider<EntregaController, EntregaState>(EntregaController.new);

/// Texto de búsqueda simple (Notifier en lugar de StateProvider, compatible con Riverpod 2.x y 3.x).
class ConsultaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String valor) => state = quitarEmojis(valor);
}

final consultaSolicitantesProvider =
    NotifierProvider<ConsultaNotifier, String>(ConsultaNotifier.new);
const registrosPorPagina = 8;

/// Página actual de cada tabla. Al cambiar la búsqueda o los filtros vuelve a la página 1.
class PaginaSolicitantesNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(consultaSolicitantesProvider);
    return 1;
  }

  void set(int pagina) => state = pagina;
}

class PaginaMaterialesNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(filtroMaterialesProvider);
    return 1;
  }

  void set(int pagina) => state = pagina;
}

class PaginaActivosNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(consultaActivosProvider);
    return 1;
  }

  void set(int pagina) => state = pagina;
}

final paginaSolicitantesProvider =
    NotifierProvider<PaginaSolicitantesNotifier, int>(PaginaSolicitantesNotifier.new);
final paginaMaterialesProvider =
    NotifierProvider<PaginaMaterialesNotifier, int>(PaginaMaterialesNotifier.new);

final solicitantesProvider = FutureProvider.autoDispose<Pagina<Solicitante>>((ref) {
  final q = ref.watch(consultaSolicitantesProvider);
  final p = ref.watch(paginaSolicitantesProvider);
  return ref
      .watch(ventanillaRepositorioProvider)
      .buscarSolicitantes(q, pagina: p, porPagina: registrosPorPagina);
});

/// Supervisores del campus del usuario, usados solo como sugerencia en el campo
/// opcional "Autorizó". Se vuelve a pedir cuando cambia el usuario con sesión:
/// si no, tras cerrar sesión otro usuario vería los de otro campus.
final supervisoresProvider = FutureProvider<List<Supervisor>>((ref) {
  ref.watch(controladorSesionProvider.select((s) => s.value?.usuario.id));
  return ref.watch(ventanillaRepositorioProvider).listarSupervisores();
});

const _noCambia = Object();

/// Filtros de la pantalla de materiales (búsqueda, categoría, tipo, almacén y "Más comunes").
class FiltroMateriales {
  const FiltroMateriales({
    this.consulta = '',
    this.categoria,
    this.tipo,
    this.almacen,
    this.soloComunes = true, // el prototipo abre con "Más comunes" seleccionado
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

  void setConsulta(String v) => state = state.copyWith(consulta: quitarEmojis(v));
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

final materialesProvider = FutureProvider.autoDispose<Pagina<MaterialCatalogo>>((ref) {
  final f = ref.watch(filtroMaterialesProvider);
  final p = ref.watch(paginaMaterialesProvider);
  return ref.watch(ventanillaRepositorioProvider).buscarMateriales(
        consulta: f.consulta,
        categoria: f.categoria,
        tipo: f.tipo,
        almacen: f.almacen,
        soloComunes: f.soloComunes,
        pagina: p,
        porPagina: registrosPorPagina,
      );
});

final consultaActivosProvider =
    NotifierProvider<ConsultaNotifier, String>(ConsultaNotifier.new);
final paginaActivosProvider =
    NotifierProvider<PaginaActivosNotifier, int>(PaginaActivosNotifier.new);

/// Activos del campus (HU8) con su estado, paginados como la tabla de materiales.
final activosProvider = FutureProvider.autoDispose<Pagina<ActivoCatalogo>>((ref) {
  final q = ref.watch(consultaActivosProvider);
  final p = ref.watch(paginaActivosProvider);
  return ref
      .watch(ventanillaRepositorioProvider)
      .buscarActivos(q, pagina: p, porPagina: registrosPorPagina);
});
