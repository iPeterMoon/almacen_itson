import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../entrega_controlador.dart';

/// Paso 4 (Escenario 1): firma de quien entrega y de quien recibe, y quién autorizó.
/// Las firmas se mandan como PNG en base64 junto con la boleta; la app no sube archivos.
class PasoConfirmacion extends ConsumerStatefulWidget {
  const PasoConfirmacion({super.key});

  @override
  ConsumerState<PasoConfirmacion> createState() => _PasoConfirmacionState();
}

class _PasoConfirmacionState extends ConsumerState<PasoConfirmacion> {
  late final SignatureController _entrega;
  late final SignatureController _recibe;

  SignatureController _crear(Future<void> Function(SignatureController) alTerminar) {
    late final SignatureController c;
    c = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colores.texto,
      exportBackgroundColor: Colors.white,
      onDrawEnd: () => alTerminar(c),
    );
    return c;
  }

  @override
  void initState() {
    super.initState();
    final c = ref.read(entregaControllerProvider.notifier);
    _entrega = _crear((ctrl) async => c.setFirmaEntrega(await ctrl.toPngBytes()));
    _recibe = _crear((ctrl) async => c.setFirmaRecibe(await ctrl.toPngBytes()));
  }

  @override
  void dispose() {
    _entrega.dispose();
    _recibe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);
    final almacenista = ref.watch(almacenistaActualProvider);

    // "Autorizado por": quien se eligió en "Autorizó (Opcional)" del paso 1, más quienes
    // autorizaron excepciones de materiales (periodicidad o límite de zona). Sin repetidos.
    final catalogo = ref.watch(autorizadoresProvider).value ?? const [];
    final autorizadores = <String>{
      if (e.autorizoId != null)
        ...catalogo.where((a) => a.id == e.autorizoId).map((a) => a.nombre),
      ...e.autorizadoPor,
    }.toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        TarjetaSeccion(
          titulo: 'Firmas y autorización',
          subtitulo: 'Revisa las firmas y el estado de autorización.',
          child: Column(children: [
            _BloqueFirma(
              etiqueta: 'Entregado por:',
              nombre: almacenista,
              controlador: _entrega,
              alLimpiar: () => c.setFirmaEntrega(null),
            ),
            const SizedBox(height: 12),
            _BloqueFirma(
              etiqueta: 'Recibido por:',
              nombre: e.recibidoPor,
              controlador: _recibe,
              alLimpiar: () => c.setFirmaRecibe(null),
            ),
            if (autorizadores.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16), border: Border.all(color: Colores.borde)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Autorizado por',
                      style: TextStyle(color: Colores.textoSuave, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(autorizadores.join(', '),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
              ),
            ],
            if (e.error != null) ...[
              const SizedBox(height: 12),
              AvisoCaja(tipo: TipoAviso.error, mensaje: e.error!),
            ],
          ]),
        ),
      ],
    );
  }
}

class _BloqueFirma extends StatelessWidget {
  const _BloqueFirma({
    required this.etiqueta,
    required this.nombre,
    required this.controlador,
    required this.alLimpiar,
  });

  final String etiqueta;
  final String nombre;
  final SignatureController controlador;
  final VoidCallback alLimpiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16), border: Border.all(color: Colores.borde)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiqueta, style: const TextStyle(color: Colores.textoSuave, fontSize: 13)),
        const SizedBox(height: 4),
        Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
            label: 'Área de firma de $nombre',
            child: Signature(
                controller: controlador, height: 150, backgroundColor: Colores.filaAlterna),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              controlador.clear();
              alLimpiar();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Limpiar firma'),
          ),
        ),
      ]),
    );
  }
}
