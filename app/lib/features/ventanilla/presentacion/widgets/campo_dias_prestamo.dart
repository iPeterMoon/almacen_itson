import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/dias_prestamo.dart';
import '../../datos/modelos.dart';
import '../entrega_controlador.dart';

/// Días de préstamo de una herramienta (HU8): contador que también se puede escribir,
/// con la fecha prevista de devolución (hoy + días, hora de Hermosillo) debajo.
/// Con los días vacíos o en 0 no hay fecha: se muestra el motivo por el que la boleta
/// no avanza. Se usa en "Seleccionados" y en el diálogo "Materiales a entregar".
class CampoDiasPrestamo extends ConsumerWidget {
  const CampoDiasPrestamo({super.key, required this.item});

  final ItemActivo item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(entregaControllerProvider.notifier);
    final ahora = ref.watch(relojProvider)();
    final codigo = item.activo.codigo;
    final equipo = item.activo.equipo;
    final dias = item.dias;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ContadorCompacto(
          valor: dias,
          sufijo: 'días',
          etiquetaMenos: 'Disminuir días de $equipo',
          etiquetaMas: 'Aumentar días de $equipo',
          etiquetaCampo: 'Días de préstamo de $equipo',
          // Con 0 días (campo vacío) "-" no aplica; con el máximo, "+" tampoco.
          onMenos: dias > diasPrestamoMinimo ? () => c.cambiarDias(codigo, dias - 1) : null,
          onMas: dias < diasPrestamoMaximo ? () => c.cambiarDias(codigo, dias + 1) : null,
          onEscribir: (texto) => c.escribirDias(codigo, texto),
        ),
        const SizedBox(height: 4),
        if (diasPrestamoValidos(dias))
          Text('Devolución prevista: ${fechaPrevistaTexto(ahora, dias)}',
              style: const TextStyle(fontSize: 13, color: Colores.textoSuave))
        else
          const Text(mensajeDiasInvalidos,
              style: TextStyle(fontSize: 13, color: Colores.peligro, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
