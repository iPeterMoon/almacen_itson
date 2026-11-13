import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../../../../core/errores/error_negocio.dart';
import '../entrega_controlador.dart';
import 'dialogo_autorizacion.dart';

Future<void> mostrarDialogoListaMateriales(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const DialogoListaMateriales());

/// "Materiales a entregar": permite ajustar cantidad, unidad, días de préstamo o quitar partidas.
class DialogoListaMateriales extends ConsumerWidget {
  const DialogoListaMateriales({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(children: [
                  const Text('Lista de Materiales',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (estado.materiales.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aún no hay materiales.',
                            style: TextStyle(color: Colores.textoSuave))),
                  for (final m in estado.materiales) _FilaMaterial(item: m, c: c),
                  const SizedBox(height: 20),
                  const Text('Lista de equipos',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (estado.activos.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aún no hay equipos.', style: TextStyle(color: Colores.textoSuave))),
                  for (final a in estado.activos) _FilaActivo(item: a, c: c),
                ]),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Al subir la cantidad el servidor vuelve a validar: si ahora rompe la periodicidad
// o el límite de la zona se piden motivo y autorización, como al agregar.
Future<void> _cambiarCantidad(
    BuildContext context, EntregaController c, ItemMaterial item, double cantidad) async {
  final mensajero = ScaffoldMessenger.of(context);
  try {
    final alerta = await c.cambiarCantidad(item.material.codigo, cantidad);
    if (alerta == null || !context.mounted) return;
    final autorizacion = await showDialog<Autorizacion>(
      context: context,
      builder: (_) => DialogoAutorizacion(
          material: item.material, cantidad: cantidad, unidad: item.unidad, alerta: alerta),
    );
    if (autorizacion != null) {
      c.cambiarCantidadAutorizada(item.material.codigo, cantidad, autorizacion);
    }
  } on ErrorNegocio catch (e) {
    mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
  } catch (_) {
    mensajero.showSnackBar(
        const SnackBar(content: Text('No se pudo conectar con el servidor.')));
  }
}

class _BotonBorrar extends StatelessWidget {
  const _BotonBorrar(this.onPressed);
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
        tooltip: 'Quitar',
        style: IconButton.styleFrom(
            backgroundColor: Colores.peligroFondo, foregroundColor: Colores.peligro),
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outline),
      );
}

class _Cantidad extends StatelessWidget {
  const _Cantidad({required this.texto, required this.onMenos, required this.onMas});
  final String texto;
  final VoidCallback onMenos;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Disminuir', onPressed: onMenos, icon: const Icon(Icons.remove)),
        SizedBox(
            width: 28,
            child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
        IconButton(tooltip: 'Aumentar', onPressed: onMas, icon: const Icon(Icons.add)),
      ]);
}

class _FilaMaterial extends StatelessWidget {
  const _FilaMaterial({required this.item, required this.c});
  final ItemMaterial item;
  final EntregaController c;

  @override
  Widget build(BuildContext context) {
    final m = item.material;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 150,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.alias, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(m.almacen, style: const TextStyle(color: Colores.textoSuave, fontSize: 12)),
              if (item.autorizacion != null)
                const Text('Con autorización',
                    style: TextStyle(color: Colores.avisoTexto, fontSize: 12)),
            ]),
          ),
          _Cantidad(
            texto: formatearCantidad(item.cantidad),
            onMenos: () => _cambiarCantidad(context, c, item, item.cantidad - 1),
            onMas: () => _cambiarCantidad(context, c, item, item.cantidad + 1),
          ),
          SizedBox(
            width: 150,
            child: CampoSelector<String>(
              etiqueta: 'Unidad',
              valor: item.unidad,
              items: [for (final u in m.unidades) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) {
                if (v != null) c.cambiarUnidad(m.codigo, v);
              },
            ),
          ),
          _BotonBorrar(() => c.quitarMaterial(m.codigo)),
        ],
      ),
    );
  }
}

class _FilaActivo extends StatelessWidget {
  const _FilaActivo({required this.item, required this.c});
  final ItemActivo item;
  final EntregaController c;

  @override
  Widget build(BuildContext context) {
    final a = item.activo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 190,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.equipo, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${a.codigo} · ${a.modelo}',
                  style: const TextStyle(color: Colores.textoSuave, fontSize: 12)),
              Text('Serie ${a.serie}', style: const TextStyle(color: Colores.textoSuave, fontSize: 12)),
            ]),
          ),
          _Cantidad(
            texto: '${item.dias}',
            onMenos: () => c.cambiarDias(a.codigo, item.dias - 1),
            onMas: () => c.cambiarDias(a.codigo, item.dias + 1),
          ),
          const Text('días'),
          _BotonBorrar(() => c.quitarActivo(a.codigo)),
        ],
      ),
    );
  }
}
