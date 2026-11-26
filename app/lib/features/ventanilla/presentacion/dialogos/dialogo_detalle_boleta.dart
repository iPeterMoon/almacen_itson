import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errores/error_negocio.dart';
import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/boletas_repositorio.dart' show formatearFechaHora;
import '../../datos/detalle_boleta.dart';
import '../../datos/historial_entregas_repositorio.dart';
import '../widgets/seleccion_activos.dart' show EtiquetaEstadoActivo;

/// HU11: "Detalles de entrega" de una boleta del historial (Figma).
/// Datos generales, materiales, herramientas prestadas (si hubo) y quién autorizó (si hubo).
Future<void> mostrarDetalleBoleta(BuildContext context, int boletaId) {
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoDetalleBoleta(boletaId: boletaId),
  );
}

class DialogoDetalleBoleta extends ConsumerWidget {
  const DialogoDetalleBoleta({super.key, required this.boletaId});

  final int boletaId;

  static const encabezadosMateriales = ['Código', 'Concepto', 'Almacén', 'Cantidad entregada'];
  static const encabezadosPrestamos = [
    'Código activo',
    'Activo',
    'Modelo',
    'Número de serie',
    'Estado actual',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(detalleBoletaProvider(boletaId));

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Detalles de entrega',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colores.texto)),
            const SizedBox(height: 16),
            Flexible(
              child: switch (detalle) {
                AsyncData(:final value) => _Contenido(detalle: value),
                AsyncError(:final error) => _Error(
                    error: error,
                    onReintentar: () => ref.invalidate(detalleBoletaProvider(boletaId)),
                  ),
                _ => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.detalle});

  final DetalleBoleta detalle;

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    final datos = [
      ('Solicitante', d.solicitante),
      ('Dependencia', d.dependencia),
      ('Entregada por', d.entregadoPor),
      ('Fecha y hora', d.entregadoEn == null ? null : formatearFechaHora(d.entregadoEn)),
      ('Unidad', d.unidad),
      ('Campus', d.campus),
    ];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Folio ${d.folio}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colores.texto)),
        const SizedBox(height: 16),
        _DatosGenerales(datos: datos),
        if (d.materiales.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _TituloSeccion('Materiales'),
          const SizedBox(height: 12),
          TablaDatos(
            encabezados: DialogoDetalleBoleta.encabezadosMateriales,
            flex: const [2, 4, 4, 3],
            filas: [
              for (final m in d.materiales)
                [m.codigo, m.concepto, m.almacen ?? '—', m.cantidadTexto],
            ],
          ),
        ],
        // Las herramientas prestadas solo aparecen si la boleta las tuvo.
        if (d.herramientas.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _TituloSeccion('Préstamos'),
          const SizedBox(height: 12),
          TablaDatos(
            encabezados: DialogoDetalleBoleta.encabezadosPrestamos,
            flex: const [3, 3, 3, 3, 3],
            filas: [
              for (final h in d.herramientas)
                [
                  h.codigo,
                  h.nombre,
                  h.modelo ?? '—',
                  h.numeroSerie ?? '—',
                  EtiquetaEstadoActivo.texto(h.estado),
                ],
            ],
            // El estado actual va como etiqueta de color, igual que en la selección de activos.
            celda: (fila, columna) => columna == 4
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: EtiquetaEstadoActivo(d.herramientas[fila].estado),
                  )
                : null,
          ),
        ],
        // Solo si la entrega requirió autorización. El servidor no guarda la hora de la
        // autorización (se pide fuera de la app, antes de entregar): se muestra la de la entrega.
        if (d.requirioAutorizacion) ...[
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Autorizada por ${d.autorizoNombre!.trim()}',
                style: const TextStyle(color: Colores.exitoOscuro),
              ),
              if (d.entregadoEn != null)
                TextSpan(
                  text: ' · ${formatearFechaHora(d.entregadoEn)}',
                  style: const TextStyle(color: Colores.texto),
                ),
            ]),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ]),
    );
  }
}

/// "Etiqueta: valor" en dos columnas, como el Figma; en pantallas angostas, una.
class _DatosGenerales extends StatelessWidget {
  const _DatosGenerales({required this.datos});

  final List<(String, String?)> datos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      const separacion = 16.0;
      final ancho = caja.maxWidth >= 480 ? (caja.maxWidth - separacion) / 2 : caja.maxWidth;
      return Wrap(
        spacing: separacion,
        runSpacing: 14,
        children: [
          for (final (etiqueta, valor) in datos)
            SizedBox(
              width: ancho,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$etiqueta: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: (valor == null || valor.trim().isEmpty) ? '—' : valor),
              ])),
            ),
        ],
      );
    });
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colores.texto));
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onReintentar});

  final Object error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final mensaje = error is ErrorNegocio
        ? (error as ErrorNegocio).mensaje
        : 'No se pudo cargar el detalle de la boleta.';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      AvisoCaja(tipo: TipoAviso.error, mensaje: mensaje),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
    ]);
  }
}
