import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../entrega_controlador.dart';

const _motivos = ['Producto dañado', 'Mayor uso de lo esperado', 'Evento', 'Pérdida o robo'];

/// Escenarios 8 y 10: muestra la restricción y solo permite continuar con motivo y autorización.
/// Devuelve la [Autorizacion] capturada, o null si se cancela.
/// SUPUESTO: el servidor valida la autorización al registrar la entrega; aquí solo se captura.
class DialogoAutorizacion extends ConsumerStatefulWidget {
  const DialogoAutorizacion({
    super.key,
    required this.material,
    required this.cantidad,
    required this.unidad,
    required this.alerta,
  });

  final MaterialCatalogo material;
  final double cantidad;
  final String unidad;
  final AlertaRestriccion alerta;

  @override
  ConsumerState<DialogoAutorizacion> createState() => _DialogoAutorizacionState();
}

class _DialogoAutorizacionState extends ConsumerState<DialogoAutorizacion> {
  String? _motivo;
  String? _autorizadorId;
  final _otro = TextEditingController();

  @override
  void dispose() {
    _otro.dispose();
    super.dispose();
  }

  bool get _completo => _motivo != null || _otro.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final a = widget.alerta;
    final autorizadores = ref.watch(autorizadoresProvider);
    final pedido = '${formatearCantidad(widget.cantidad)} ${widget.unidad}';

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text('Límite de material alcanzado (Requiere autorización)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              AvisoCaja(tipo: TipoAviso.advertencia, titulo: a.titulo, mensaje: a.regla),
              const SizedBox(height: 16),
              Wrap(spacing: 32, runSpacing: 12, children: [
                _Bloque('Material', ['Alias: ${widget.material.alias}', 'Concepto: ${widget.material.concepto}']),
                _Bloque('Cantidad', [pedido]),
              ]),
              const SizedBox(height: 12),
              if (a.tipo == TipoAlerta.periodicidad)
                Wrap(spacing: 32, runSpacing: 12, children: [
                  _Bloque('Última entrega', [a.ultimaEntrega ?? '-'], suave: true),
                  _Bloque('Próxima entrega hasta', [a.proximaEntrega ?? '-'], suave: true),
                  if (a.diasFaltantes != null)
                    _Bloque('Días que faltan', ['${a.diasFaltantes}'], suave: true),
                ])
              else
                Wrap(spacing: 32, runSpacing: 12, children: [
                  _Bloque('Ya entregado', [a.entregado ?? '-'], suave: true),
                  _Bloque('Solicitado ahora', [a.solicitado ?? pedido], suave: true),
                ]),
              const SizedBox(height: 16),
              autorizadores.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const AvisoCaja(
                    tipo: TipoAviso.error, mensaje: 'No se pudo cargar la lista de autorizadores.'),
                data: (lista) => CampoSelector<String>(
                  etiqueta: 'Solicitar autorización a',
                  valor: _autorizadorId ?? (lista.isEmpty ? null : lista.first.id),
                  items: [for (final x in lista) DropdownMenuItem(value: x.id, child: Text(x.nombre))],
                  onChanged: (v) => setState(() => _autorizadorId = v),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Motivo', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final m in _motivos)
                  ChoiceChip(
                    label: Text(m),
                    selected: _motivo == m,
                    onSelected: (s) => setState(() => _motivo = s ? m : null),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _otro,
                minLines: 3,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Otro', alignLabelWithHint: true),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: !_completo || !autorizadores.hasValue
                        ? null
                        : () {
                            final lista = autorizadores.value!;
                            final elegido = lista.firstWhere(
                                (x) => x.id == (_autorizadorId ?? lista.first.id),
                                orElse: () => lista.first);
                            Navigator.pop(
                              context,
                              Autorizacion(
                                autorizadorId: elegido.id,
                                autorizadorNombre: elegido.nombre,
                                motivo: _motivo ?? 'Otro',
                                detalleOtro: _otro.text.trim(),
                              ),
                            );
                          },
                    child: const Text('Autorizar'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque(this.titulo, this.lineas, {this.suave = false});
  final String titulo;
  final List<String> lineas;
  final bool suave;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: suave ? Colores.textoSuave : Colores.texto)),
          const SizedBox(height: 4),
          for (final l in lineas) Text(l),
        ],
      );
}
