import 'package:almacen_itson/core/validacion/limites_texto.dart';
import 'package:almacen_itson/core/validacion/sin_emojis.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';

const _motivos = ['Producto dañado', 'Mayor uso de lo esperado', 'Evento', 'Pérdida o robo'];

/// Escenarios 8 y 10: avisa de que se excedió la periodicidad o el límite de la
/// zona, sugiere solicitar autorización fuera del sistema y exige el motivo.
/// La boleta se entrega de inmediato: aquí no se registra ninguna autorización.
/// Devuelve el [MotivoExcepcion] capturado, o null si se cancela.
class DialogoSugerenciaAutorizacion extends StatefulWidget {
  const DialogoSugerenciaAutorizacion({
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
  State<DialogoSugerenciaAutorizacion> createState() => _DialogoSugerenciaAutorizacionState();
}

class _DialogoSugerenciaAutorizacionState extends State<DialogoSugerenciaAutorizacion> {
  String? _motivo;
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
                child: Text('Se sugiere solicitar autorización',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              AvisoCaja(
                tipo: TipoAviso.info,
                titulo: a.titulo,
                mensaje:
                    '${a.regla} La boleta se entregará de inmediato: captura el motivo de la '
                    'excepción y solicita la autorización fuera del sistema.',
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 32, runSpacing: 12, children: [
                _Bloque('Material', [
                  'Alias: ${widget.material.alias}',
                  'Concepto: ${widget.material.concepto}'
                ]),
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
              const Text('Motivo de la excepción', style: TextStyle(fontWeight: FontWeight.w700)),
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
                maxLength: limiteComentario,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: formattersSinEmojis,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Otro',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: !_completo
                        ? null
                        : () => Navigator.pop(
                              context,
                              MotivoExcepcion(
                                motivo: _motivo ?? 'Otro',
                                detalleOtro: quitarEmojis(_otro.text.trim()),
                              ),
                            ),
                    child: const Text('Continuar'),
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
