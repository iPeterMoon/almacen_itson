import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/archivos/guardador_archivos.dart';
import '../../../../core/archivos/selector_archivos.dart';
import '../../../../core/errores/error_negocio.dart';
import '../../../../core/tema/tema.dart';
import '../dialogos/dialogo_errores_importacion.dart';
import '../historial_entregas_controlador.dart';
import '../importacion_entregas_controlador.dart';

/// Copia de servidor/plantillas/ (una prueba verifica que sean iguales).
const nombrePlantillaImportacion = 'plantilla-importar-entregas.xlsx';
const rutaPlantillaImportacion = 'assets/plantillas/$nombrePlantillaImportacion';

const textoDescargarPlantilla = 'Descargar plantilla de ejemplo';

String mensajeImportadas(int n) => n == 1 ? 'Se importó 1 boleta' : 'Se importaron $n boletas';

/// Se agrega al aviso si hay filtros: las entregas anteriores suelen quedar fuera del rango.
const textoQuitarFiltros = 'Quita los filtros para verlas todas.';

/// HU11 (escenario 6): opción para importar entregas anteriores desde Excel, con el
/// progreso del envío y la descarga de la plantilla de ejemplo.
class ImportarEntregas extends ConsumerStatefulWidget {
  const ImportarEntregas({super.key});

  @override
  ConsumerState<ImportarEntregas> createState() => _ImportarEntregasState();
}

class _ImportarEntregasState extends ConsumerState<ImportarEntregas>
    with AutomaticKeepAliveClientMixin {
  // Se está eligiendo el archivo o guardando la plantilla: evita repetirlo con un doble toque.
  bool _ocupado = false;

  // La pantalla es un ListView: sin esto, desplazarse durante el envío destruiría
  // el widget y no se mostraría el resultado.
  @override
  bool get wantKeepAlive => true;

  // Ocupado o enviando el Excel: ningún botón responde (evita trabajos encimados).
  bool get _bloqueado => _ocupado || ref.read(importacionEntregasProvider).enviando;

  Future<void> _importar() async {
    if (_bloqueado) return;
    setState(() => _ocupado = true);
    try {
      final archivo = await ref.read(proveedorSelectorArchivos).elegirXlsx();
      if (!mounted || archivo == null) return;
      setState(() => _ocupado = false);

      final resultado = await ref.read(importacionEntregasProvider.notifier).importar(archivo);
      if (!mounted || resultado == null) return;
      if (resultado.exitosa) {
        final historial = ref.read(historialEntregasProvider.notifier);
        final filtrado = historial.hayFechas || historial.buscando;
        _avisar([
          '${mensajeImportadas(resultado.importadas)}.',
          if (filtrado) textoQuitarFiltros,
        ].join(' '));
      } else {
        await mostrarDialogoErroresImportacion(context, resultado.errores);
      }
    } on ErrorNegocio catch (e) {
      _avisar(e.mensaje);
    } catch (_) {
      _avisar('No se pudo importar el archivo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _descargarPlantilla() async {
    if (_bloqueado) return;
    setState(() => _ocupado = true);
    try {
      final datos = await rootBundle.load(rutaPlantillaImportacion);
      // Igual que "Exportar Excel": directo a Descargas, sin preguntar dónde.
      final carpeta = await ref
          .read(proveedorGuardadorArchivos)
          .guardarEnDescargas(
            nombre: nombrePlantillaImportacion,
            bytes: datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes),
          );
      _avisar('Se guardó $nombrePlantillaImportacion en $carpeta.');
    } on ErrorNegocio catch (e) {
      _avisar(e.mensaje);
    } catch (_) {
      _avisar('No se pudo guardar la plantilla.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final estado = ref.watch(importacionEntregasProvider);
    final bloqueado = _ocupado || estado.enviando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Una sola línea: la pantalla ya es larga y otra fila empujaría "Exportar Excel"
        // y la paginación fuera de la vista.
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: bloqueado ? null : _descargarPlantilla,
              tooltip: textoDescargarPlantilla,
              color: Colores.primario,
              icon: const Icon(Icons.description_outlined),
            ),
            const SizedBox(width: 4),
            // Flexible: en pantallas angostas el texto pasa a dos líneas en vez de desbordarse.
            Flexible(
              child: OutlinedButton.icon(
                onPressed: bloqueado ? null : _importar,
                icon: const Icon(Icons.upload_outlined, color: Colores.primario),
                label: const Text(
                  'Importar entregas anteriores desde Excel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (estado.enviando) ...[const SizedBox(height: 12), _Progreso(progreso: estado.progreso)],
      ],
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.progreso});

  final double progreso;

  @override
  Widget build(BuildContext context) {
    final enviado = progreso >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          enviado
              ? 'Validando e importando las boletas…'
              : 'Enviando archivo… ${(progreso * 100).floor()} %',
          style: const TextStyle(color: Colores.textoSuave),
        ),
        const SizedBox(height: 6),
        // Ya enviado no se sabe cuánto falta: la barra queda en movimiento.
        LinearProgressIndicator(value: enviado ? null : progreso),
      ],
    );
  }
}
