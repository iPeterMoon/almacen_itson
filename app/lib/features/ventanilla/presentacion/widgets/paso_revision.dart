import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../dialogos/dialogo_comentario.dart';
import '../entrega_controlador.dart';

/// Paso 3. Escenario 5: cada material con su cantidad y comentario opcional antes de confirmar.
/// Diseño del prototipo: dos tarjetas (Materiales y Activos) con tabla y botón "Comentario" por fila.
class PasoRevision extends ConsumerWidget {
  const PasoRevision({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        TarjetaSeccion(
          titulo: 'Lista de materiales y equipo solicitados',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SubTarjeta(
              titulo: 'Materiales',
              child: e.materiales.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Sin materiales.', style: TextStyle(color: Colores.textoSuave)))
                  : _TablaRevision(
                      encabezados: const ['Entregado', 'Material', 'Cantidad', 'Almacén', 'Ubicación', 'Acciones'],
                      flex: const [2, 3, 3, 3, 3, 3],
                      filas: [
                        for (final it in e.materiales)
                          [
                            Checkbox(
                                value: it.entregado,
                                onChanged: (v) => c.marcarMaterial(it.material.codigo, v ?? false)),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(it.material.alias),
                              if (it.autorizacion != null)
                                const Text('Entrega autorizada',
                                    style: TextStyle(color: Colores.avisoTexto, fontSize: 11)),
                            ]),
                            Text(it.cantidadTexto),
                            Text(it.material.almacen),
                            Text(it.material.ubicacion),
                            _BotonComentario(
                              comentado: (it.comentario ?? '').isNotEmpty,
                              onPressed: () async {
                                final t = await mostrarDialogoComentario(context,
                                    nombre: it.material.alias,
                                    detalle: it.cantidadTexto,
                                    inicial: it.comentario);
                                if (t != null) c.comentarMaterial(it.material.codigo, t);
                              },
                            ),
                          ]
                      ],
                    ),
            ),
            if (e.activos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SubTarjeta(
                titulo: 'Activos',
                child: _TablaRevision(
                  encabezados: const ['Entregado', 'Activo', 'Equipo', 'Modelo', 'N° Serie', 'Acciones'],
                  flex: const [2, 2, 3, 3, 3, 3],
                  filas: [
                    for (final it in e.activos)
                      [
                        Checkbox(
                            value: it.entregado,
                            onChanged: (v) => c.marcarActivo(it.activo.codigo, v ?? false)),
                        Text(it.activo.codigo),
                        Text(it.activo.equipo),
                        Text(it.activo.modelo),
                        Text(it.activo.serie),
                        _BotonComentario(
                          comentado: (it.comentario ?? '').isNotEmpty,
                          onPressed: () async {
                            final t = await mostrarDialogoComentario(context,
                                nombre: it.activo.equipo,
                                detalle: it.activo.modelo,
                                inicial: it.comentario);
                            if (t != null) c.comentarActivo(it.activo.codigo, t);
                          },
                        ),
                      ]
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: c.todoMarcado,
              onChanged: (v) => c.marcarTodo(v ?? false),
              title: const Text('Marcar Todo'),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Tarjeta interna con título (Materiales / Activos).
class _SubTarjeta extends StatelessWidget {
  const _SubTarjeta({required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colores.borde),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(titulo,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colores.texto)),
          ),
          child,
        ]),
      );
}

/// Tabla sin borde: encabezado en gris y filas alternadas. Se desplaza si la pantalla es angosta.
class _TablaRevision extends StatelessWidget {
  const _TablaRevision({
    required this.encabezados,
    required this.flex,
    required this.filas,
    this.anchoMinimo = 600,
  });

  final List<String> encabezados;
  final List<int> flex;
  final List<List<Widget>> filas;
  final double anchoMinimo;

  Widget _fila(List<Widget> celdas, {Color? color}) => Container(
        color: color,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          for (var k = 0; k < celdas.length; k++)
            Expanded(
              flex: flex[k],
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Align(alignment: Alignment.centerLeft, child: celdas[k]),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth < anchoMinimo ? anchoMinimo : caja.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: ancho,
          child: Column(children: [
            _fila([
              for (final h in encabezados)
                Text(h,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: Colores.textoSuave)),
            ]),
            for (var i = 0; i < filas.length; i++)
              _fila(
                [for (final w in filas[i]) DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: w)],
                color: i.isEven ? Colores.filaAlterna : null,
              ),
          ]),
        ),
      );
    });
  }
}

class _BotonComentario extends StatelessWidget {
  const _BotonComentario({required this.comentado, required this.onPressed});
  final bool comentado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: Colores.primario,
          side: const BorderSide(color: Colores.borde),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (comentado) ...[
            const Icon(Icons.check_circle_outline, size: 16),
            const SizedBox(width: 4),
          ],
          const Text('Comentario', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
