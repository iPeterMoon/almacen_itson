import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/barra_navegacion.dart';
import '../../../core/widgets/componentes.dart';
import '../datos/boletas_repositorio.dart';
import '../datos/historial_entregas_repositorio.dart';
import '../datos/modelos.dart';
import 'dialogos/dialogo_detalle_boleta.dart';
import 'exportar_historial_controlador.dart';
import 'historial_entregas_controlador.dart';
import 'ventanilla_rutas.dart';
import 'widgets/encabezado_ventanilla.dart';

/// HU11: pantalla principal de Ventanilla con el historial de entregas paginado,
/// el buscador por solicitante o folio, el filtro por fechas inline y el botón
/// "+ Nueva entrega".
class HistorialEntregasPage extends ConsumerStatefulWidget {
  const HistorialEntregasPage({super.key});

  static const encabezados = ['Folio', 'Solicitante', 'Dependencia', 'Fecha y hora', 'Supervisor'];

  /// Espera desde la última tecla antes de consultar, igual que la búsqueda de materiales.
  static const esperaBusqueda = Duration(milliseconds: 300);

  @override
  ConsumerState<HistorialEntregasPage> createState() => _HistorialEntregasPageState();
}

// Solo los caracteres que acepta el servidor en `q` (letras, números, espacios y
// . - / # '): así nunca se manda una búsqueda que respondería 400. Tampoco deja pasar emojis.
final _caracteresBusqueda =
    FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{N} .\-/#']", unicode: true));

class _HistorialEntregasPageState extends ConsumerState<HistorialEntregasPage> {
  Timer? _espera;
  final _campo = TextEditingController();

  /// 0 = eligiendo "Desde", 1 = eligiendo "Hasta", null = calendario cerrado.
  /// El calendario se despliega dentro de la tarjeta: no abre otra pantalla ni diálogo.
  int? _editandoFecha;

  @override
  void dispose() {
    _espera?.cancel();
    _campo.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(HistorialEntregasPage.esperaBusqueda,
        () => ref.read(historialEntregasProvider.notifier).buscar(texto));
  }

  // La "x" del campo regresa al historial completo sin esperar.
  void _limpiar() {
    _espera?.cancel();
    _campo.clear();
    ref.read(historialEntregasProvider.notifier).buscar('');
  }

  String _formatoFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/${f.year}';

  void _elegirFecha(DateTime dia) {
    final notifier = ref.read(historialEntregasProvider.notifier);
    final elegida = DateTime(dia.year, dia.month, dia.day);
    if (_editandoFecha == 0) {
      final hasta = notifier.hasta;
      // Si el nuevo "Desde" pasa el "Hasta" actual, el rango se vuelve ese único día.
      notifier.filtrarPorFechas(
          elegida, hasta: hasta != null && elegida.isAfter(hasta) ? elegida : hasta);
    } else {
      notifier.filtrarPorFechas(notifier.desde, hasta: elegida);
    }
    setState(() => _editandoFecha = null);
  }

  @override
  Widget build(BuildContext context) {
    final historial = ref.watch(historialEntregasProvider);
    final notifier = ref.read(historialEntregasProvider.notifier);
    final hoy = DateTime.now();
    final hoyMidnight = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaInicial = _editandoFecha == 1
        ? (notifier.hasta ?? notifier.desde ?? hoyMidnight)
        : (notifier.desde ?? hoyMidnight);

    return Scaffold(
      appBar: const EncabezadoVentanilla(),
      bottomNavigationBar: const BarraNavegacionInferior(actual: SeccionApp.ventanilla),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    // Pendiente: importar entregas anteriores desde Excel (otro ticket).
                    onPressed: () {},
                    icon: const Icon(Icons.upload_outlined, color: Colores.primario),
                    label: const Text('Importar entregas anteriores desde Excel',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                TarjetaSeccion(
                  titulo: 'Historial de entregas',
                  subtitulo: 'Registro de entregas de material y/o equipos.',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ValueListenableBuilder(
                      valueListenable: _campo,
                      builder: (context, valor, _) => TextField(
                        controller: _campo,
                        inputFormatters: [_caracteresBusqueda, LengthLimitingTextInputFormatter(100)],
                        onChanged: _buscar,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar por solicitante o folio',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (valor.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Borrar búsqueda',
                                  onPressed: _limpiar,
                                  icon: const Icon(Icons.close),
                                ),
                              IconButton(
                                tooltip: 'Filtrar por fecha',
                                onPressed: () => setState(() => _editandoFecha ??= 0),
                                icon: const Icon(Icons.calendar_month_outlined),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // El selector vive en esta tarjeta: el icono del buscador abre el
                    // calendario debajo, sin navegar a otra pantalla ni mostrar un diálogo.
                    if (notifier.hayFechas) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _editandoFecha = 0),
                            icon: const Icon(Icons.calendar_today_outlined, size: 18),
                            label: Text(
                              notifier.desde == null ? 'Desde' : _formatoFecha(notifier.desde!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _editandoFecha = 1),
                            icon: const Icon(Icons.calendar_today_outlined, size: 18),
                            label: Text(
                              notifier.hasta == null ? 'Hasta' : _formatoFecha(notifier.hasta!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar filtro de fecha',
                          onPressed: () {
                            setState(() => _editandoFecha = null);
                            notifier.limpiarFechas();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ]),
                    ],
                    if (_editandoFecha != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colores.borde),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: CalendarDatePicker(
                          // initialDate solo se lee al montarse: cambiar la key al
                          // pasar de "Desde" a "Hasta" fuerza el nuevo estado.
                          key: ValueKey(_editandoFecha),
                          initialDate: fechaInicial,
                          firstDate: DateTime(2020),
                          lastDate: hoyMidnight,
                          onDateChanged: _elegirFecha,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() => _editandoFecha = null),
                          child: const Text('Cancelar'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    switch (historial) {
                      AsyncData(:final value) => _Tabla(pagina: value),
                      AsyncError(:final error) => _Error(error: error),
                      _ => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    },
                  ]),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const SizedBox(width: 168, child: _BotonExportar()),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 226,
                    child: FilledButton(
                      // VentanillaEntregaPage reinicia la boleta al abrirse; al terminar
                      // una entrega el historial se recarga solo (entregasTerminadasProvider).
                      onPressed: () => context.push(rutaNuevaEntrega),
                      child: const Text('+ Nueva entrega', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso al terminar de exportar (AI-79): dónde quedó el archivo y, si se cortó en
/// el tope del servidor, cuántas boletas no alcanzaron a entrar.
String mensajeExportacion(ExportacionHistorial r) {
  final guardado = 'Se guardó ${r.nombre} en ${r.carpeta}.';
  if (!r.recortado) return guardado;
  return '$guardado Trae solo las primeras ${ArchivoHistorial.maximoFilas} de ${r.total} entregas; '
      'usa la búsqueda o las fechas para exportar el resto.';
}

const mensajeErrorExportacion = 'No se pudo exportar el historial. Intenta de nuevo.';

/// "Exportar Excel" (AI-79): descarga el historial con los filtros activos (búsqueda
/// y fechas) y lo guarda en Descargas. Mientras exporta se desactiva y muestra un
/// indicador; al terminar avisa dónde quedó el archivo o muestra el error.
class _BotonExportar extends ConsumerWidget {
  const _BotonExportar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(exportarHistorialProvider, (anterior, estado) {
      // Solo se avisa cuando termina una exportación (de cargando a listo o error).
      if (anterior?.isLoading != true || estado.isLoading) return;
      final mensaje = switch (estado) {
        AsyncError(:final error) => error is ErrorNegocio ? error.mensaje : mensajeErrorExportacion,
        AsyncData(:final value?) => mensajeExportacion(value),
        _ => null,
      };
      if (mensaje == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(mensaje), duration: const Duration(seconds: 6)));
    });
    final exportando = ref.watch(exportarHistorialProvider).isLoading;

    return OutlinedButton.icon(
      onPressed: exportando ? null : ref.read(exportarHistorialProvider.notifier).exportar,
      icon: exportando
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download_outlined, color: Colores.primario),
      label: const Text('Exportar Excel', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _Tabla extends ConsumerWidget {
  const _Tabla({required this.pagina});

  final Pagina<EntregaHistorial> pagina;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historialEntregasProvider.notifier);
    if (pagina.total == 0) {
      final mensaje = notifier.buscando
          ? 'No hay boletas que coincidan con la búsqueda'
          : notifier.hayFechas
              ? 'No hay entregas en el rango de fechas seleccionado.'
              : 'Aún no hay entregas registradas.';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(mensaje, style: const TextStyle(color: Colores.textoSuave)),
        ),
      );
    }
    return Column(children: [
      TablaDatos(
        encabezados: HistorialEntregasPage.encabezados,
        flex: const [1, 1, 1, 1, 1],
        // Al tocar una fila se abre el detalle de esa boleta.
        onTap: (fila) => mostrarDetalleBoleta(context, pagina.items[fila].id),
        filas: [
          for (final e in pagina.items)
            [
              e.folio,
              e.solicitante,
              e.dependencia ?? '—',
              formatearFechaHora(e.entregadoEn),
              e.supervisor ?? '—',
            ],
        ],
      ),
      PaginadorTabla(
        pagina: pagina.pagina,
        totalPaginas: pagina.totalPaginas,
        mostrando: pagina.items.length,
        total: pagina.total,
        onCambiar: notifier.irAPagina,
      ),
    ]);
  }
}

class _Error extends ConsumerWidget {
  const _Error({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mensaje = error is ErrorNegocio
        ? (error as ErrorNegocio).mensaje
        : 'No se pudo cargar el historial de entregas.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AvisoCaja(tipo: TipoAviso.error, mensaje: mensaje),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: ref.read(historialEntregasProvider.notifier).recargar,
        child: const Text('Reintentar'),
      ),
    ]);
  }
}
