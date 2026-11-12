import 'package:flutter/material.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';

/// Escenario 6: avisa la existencia insuficiente y ofrece ajustar a lo disponible.
/// Devuelve true si el almacenista elige ajustar.
Future<bool?> mostrarDialogoStock(BuildContext context, StockInsuficiente s) {
  final pedido = formatearCantidad(s.solicitado);
  final hay = formatearCantidad(s.disponible);
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Existencia insuficiente',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              AvisoCaja(
                tipo: TipoAviso.error,
                titulo: s.nombre,
                mensaje: 'Se solicitan $pedido y el campus solo tiene $hay ${s.unidad}. '
                    'No se puede guardar una cantidad mayor al stock.',
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Ajustar a $hay'))),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

enum AccionResumen { volver, nueva }

/// Escenario 1: resumen con el folio de salida que genera el servidor.
Future<AccionResumen?> mostrarDialogoResumen(BuildContext context, ResumenEntrega r) {
  return showDialog<AccionResumen>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: ListView(children: [
                  Text('Folio ${r.folio}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Recibida por ${r.recibidoPor}'),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colores.fondo, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Linea('Área', r.area),
                      _Linea('Fecha y Hora', r.fechaHora),
                      _Linea('Entregado por', r.entregadoPor),
                    ]),
                  ),
                  if (r.materiales.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Materiales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _Tabla(
                        encabezados: const ['Código', 'Material', 'Cantidad'],
                        filas: [for (final l in r.materiales) [l.codigo, l.nombre, l.detalle]]),
                  ],
                  if (r.activos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Activos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _Tabla(
                        encabezados: const ['Código', 'Equipo', 'Modelo', 'Número de serie'],
                        filas: [for (final l in r.activos) [l.codigo, l.nombre, l.detalle, l.extra]]),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, AccionResumen.volver),
                    child: const Text('Volver a ventanilla')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, AccionResumen.nueva),
                    child: const Text('+ Nueva entrega')),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Linea extends StatelessWidget {
  const _Linea(this.etiqueta, this.valor);
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$etiqueta: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: valor),
        ])),
      );
}

class _Tabla extends StatelessWidget {
  const _Tabla({required this.encabezados, required this.filas});
  final List<String> encabezados;
  final List<List<String>> filas;

  @override
  Widget build(BuildContext context) {
    Widget fila(List<String> celdas, {bool encabezado = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: encabezado ? Colores.fondo : null,
            border: encabezado ? null : const Border(bottom: BorderSide(color: Colores.borde)),
          ),
          child: Row(children: [
            for (var i = 0; i < celdas.length; i++)
              Expanded(
                child: Text(celdas[i],
                    style: TextStyle(
                        fontWeight: (encabezado || i == 0) ? FontWeight.w700 : FontWeight.w400,
                        color: encabezado ? Colores.textoSuave : Colores.texto)),
              ),
          ]),
        );
    return Column(children: [fila(encabezados, encabezado: true), for (final f in filas) fila(f)]);
  }
}
