import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dialogos/dialogo_stock_y_resumen.dart';
import 'entrega_controlador.dart';
import 'widgets/indicador_pasos.dart';
import 'widgets/paso_confirmacion.dart';
import 'widgets/paso_materiales.dart';
import 'widgets/paso_revision.dart';
import 'widgets/paso_solicitante.dart';

/// HU6: Nueva entrega en ventanilla (4 pasos). Ruta sugerida: /ventanilla/nueva-entrega
class VentanillaEntregaPage extends ConsumerStatefulWidget {
  const VentanillaEntregaPage({super.key});

  @override
  ConsumerState<VentanillaEntregaPage> createState() => _VentanillaEntregaPageState();
}

class _VentanillaEntregaPageState extends ConsumerState<VentanillaEntregaPage> {
  @override
  void initState() {
    super.initState();
    // Cada vez que se abre la pantalla se empieza una boleta limpia.
    Future.microtask(() => ref.read(entregaControllerProvider.notifier).reiniciar());
  }

  void _salir() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _alCambiar(EntregaState? anterior, EntregaState nuevo) async {
    final c = ref.read(entregaControllerProvider.notifier);
    if (nuevo.resumen != null && anterior?.resumen == null) {
      final accion = await mostrarDialogoResumen(context, nuevo.resumen!);
      c.reiniciar();
      if (accion == AccionResumen.volver && mounted) _salir();
    }
    if (nuevo.stockInsuficiente != null && anterior?.stockInsuficiente == null) {
      final ajustar = await mostrarDialogoStock(context, nuevo.stockInsuficiente!);
      if (ajustar == true) {
        c.ajustarAStock();
      } else {
        c.descartarAvisoStock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EntregaState>(entregaControllerProvider, _alCambiar);
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);

    final cuerpo = switch (e.paso) {
      0 => const PasoSolicitante(),
      1 => const PasoMateriales(),
      2 => const PasoRevision(),
      _ => const PasoConfirmacion(),
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ventanilla de entregas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            Text('Entrega de material y equipo',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  IndicadorPasos(actual: e.paso),
                  Expanded(child: cuerpo),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        onPressed: e.enviando ? null : (e.paso == 0 ? _salir : c.retroceder),
                        child: Text(e.paso == 0 ? 'Cancelar' : 'Atrás'),
                      ),
                      if (e.paso < 3)
                        FilledButton(
                          onPressed: e.puedeAvanzar() ? c.avanzar : null,
                          child: const Text('Siguiente'),
                        )
                      else
                        FilledButton(
                          onPressed: e.puedeConfirmar ? c.confirmar : null,
                          child: e.enviando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Confirmar Entrega'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
