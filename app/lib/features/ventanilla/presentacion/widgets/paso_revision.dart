import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../dialogos/dialogo_comentario.dart';
import '../entrega_controlador.dart';

/// Paso 3. Escenario 5: cada material con su cantidad y comentario opcional antes de confirmar.
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
            const Text('Materiales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (e.materiales.isEmpty)
              const Text('Sin materiales.', style: TextStyle(color: Colores.textoSuave)),
            for (var i = 0; i < e.materiales.length; i++)
              _FilaRevision(
                color: i.isOdd ? Colores.filaAlterna : null,
                entregado: e.materiales[i].entregado,
                titulo: e.materiales[i].material.alias,
                detalle:
                    '${e.materiales[i].cantidadTexto} · ${e.materiales[i].material.almacen} · ${e.materiales[i].material.ubicacion}',
                comentario: e.materiales[i].comentario,
                autorizado: e.materiales[i].autorizacion != null,
                onCambio: (v) => c.marcarMaterial(e.materiales[i].material.codigo, v),
                onComentar: () async {
                  final it = e.materiales[i];
                  final t = await mostrarDialogoComentario(context,
                      nombre: it.material.alias, detalle: it.cantidadTexto, inicial: it.comentario);
                  if (t != null) c.comentarMaterial(it.material.codigo, t);
                },
              ),
            if (e.activos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Activos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (var i = 0; i < e.activos.length; i++)
                _FilaRevision(
                  color: i.isOdd ? Colores.filaAlterna : null,
                  entregado: e.activos[i].entregado,
                  titulo: '${e.activos[i].activo.codigo} · ${e.activos[i].activo.equipo}',
                  detalle:
                      '${e.activos[i].activo.modelo} · Serie ${e.activos[i].activo.serie} · ${e.activos[i].dias} día(s)',
                  comentario: e.activos[i].comentario,
                  onCambio: (v) => c.marcarActivo(e.activos[i].activo.codigo, v),
                  onComentar: () async {
                    final it = e.activos[i];
                    final t = await mostrarDialogoComentario(context,
                        nombre: it.activo.equipo, detalle: it.activo.modelo, inicial: it.comentario);
                    if (t != null) c.comentarActivo(it.activo.codigo, t);
                  },
                ),
            ],
            const SizedBox(height: 12),
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

class _FilaRevision extends StatelessWidget {
  const _FilaRevision({
    required this.entregado,
    required this.titulo,
    required this.detalle,
    required this.onCambio,
    required this.onComentar,
    this.comentario,
    this.autorizado = false,
    this.color,
  });

  final bool entregado;
  final String titulo;
  final String detalle;
  final String? comentario;
  final bool autorizado;
  final Color? color;
  final ValueChanged<bool> onCambio;
  final VoidCallback onComentar;

  @override
  Widget build(BuildContext context) {
    final tieneComentario = comentario != null && comentario!.isNotEmpty;
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Checkbox(value: entregado, onChanged: (v) => onCambio(v ?? false)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(detalle, style: const TextStyle(color: Colores.textoSuave, fontSize: 12)),
            if (autorizado)
              const Text('Entrega autorizada',
                  style: TextStyle(color: Colores.avisoTexto, fontSize: 12)),
            if (tieneComentario)
              Text('Comentario: $comentario',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ]),
        ),
        OutlinedButton(
          onPressed: onComentar,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 40), foregroundColor: Colores.primario),
          child: Text(tieneComentario ? 'Editar' : 'Comentario'),
        ),
      ]),
    );
  }
}
