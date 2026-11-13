import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../dialogos/dialogo_comentario.dart';
import '../entrega_controlador.dart';

/// Paso 3. Escenario 5: cada material con su cantidad y comentario opcional antes de confirmar.
/// Cada partida es una ficha con campos etiquetados (no una tabla apretada), para que se lea
/// cómodamente en tableta.
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
                  : ContenedorLista(children: [
                      for (var i = 0; i < e.materiales.length; i++)
                        Builder(builder: (context) {
                          final it = e.materiales[i];
                          return _FichaRevision(
                            indice: i,
                            entregado: it.entregado,
                            onCambio: (v) => c.marcarMaterial(it.material.codigo, v),
                            campos: [
                              CampoDato('Material', it.material.alias),
                              CampoDato('Cantidad', it.cantidadTexto),
                              CampoDato('Almacén', it.material.almacen),
                              CampoDato('Ubicación', it.material.ubicacion),
                            ],
                            autorizada: it.autorizacion != null,
                            comentario: it.comentario,
                            onComentar: () async {
                              final t = await mostrarDialogoComentario(context,
                                  nombre: it.material.alias,
                                  detalle: it.cantidadTexto,
                                  inicial: it.comentario);
                              if (t != null) c.comentarMaterial(it.material.codigo, t);
                            },
                          );
                        }),
                    ]),
            ),
            if (e.activos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SubTarjeta(
                titulo: 'Activos',
                child: ContenedorLista(children: [
                  for (var i = 0; i < e.activos.length; i++)
                    Builder(builder: (context) {
                      final it = e.activos[i];
                      return _FichaRevision(
                        indice: i,
                        entregado: it.entregado,
                        onCambio: (v) => c.marcarActivo(it.activo.codigo, v),
                        campos: [
                          CampoDato('Equipo', it.activo.equipo),
                          CampoDato('Activo', it.activo.codigo),
                          CampoDato('Modelo', it.activo.modelo),
                          CampoDato('N° Serie', it.activo.serie),
                          CampoDato('Préstamo', '${it.dias} día(s)'),
                        ],
                        comentario: it.comentario,
                        onComentar: () async {
                          final t = await mostrarDialogoComentario(context,
                              nombre: it.activo.equipo,
                              detalle: it.activo.modelo,
                              inicial: it.comentario);
                          if (t != null) c.comentarActivo(it.activo.codigo, t);
                        },
                      );
                    }),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: c.todoMarcado,
                onChanged: (v) => c.marcarTodo(v ?? false),
                title: const Text('Marcar Todo'),
              ),
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
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(titulo,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colores.texto)),
          ),
          child,
        ]),
      );
}

/// Ficha de una partida: casilla "Entregado", datos etiquetados y botón "Comentario".
class _FichaRevision extends StatelessWidget {
  const _FichaRevision({
    required this.indice,
    required this.entregado,
    required this.onCambio,
    required this.campos,
    required this.onComentar,
    this.comentario,
    this.autorizada = false,
  });

  final int indice;
  final bool entregado;
  final ValueChanged<bool> onCambio;
  final List<CampoDato> campos;
  final VoidCallback onComentar;
  final String? comentario;
  final bool autorizada;

  @override
  Widget build(BuildContext context) {
    final tieneComentario = comentario != null && comentario!.isNotEmpty;
    return Container(
      color: indice.isEven ? Colores.filaAlterna : Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 64,
          child: Column(children: [
            Checkbox(value: entregado, onChanged: (v) => onCambio(v ?? false)),
            const Text('Entregado', style: TextStyle(fontSize: 11, color: Colores.textoSuave)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RejillaCampos(campos: campos, anchoMinimoColumna: 150),
            if (autorizada)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Entrega autorizada',
                    style: TextStyle(color: Colores.avisoTexto, fontSize: 12)),
              ),
            if (tieneComentario)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Comentario: $comentario',
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _BotonComentario(comentado: tieneComentario, onPressed: onComentar),
        ),
      ]),
    );
  }
}

class _BotonComentario extends StatelessWidget {
  const _BotonComentario({required this.comentado, required this.onPressed});
  final bool comentado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Badge(
        // Punto verde cuando ya tiene comentario.
        isLabelVisible: comentado,
        smallSize: 10,
        backgroundColor: Colores.exitoOscuro,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: Colores.primario,
            side: const BorderSide(color: Colores.borde),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Comentario', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );
}
