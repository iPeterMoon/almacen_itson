import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../entrega_controlador.dart';
import 'campo_autorizo.dart';

/// Paso 4 (Escenario 1): firma de quien entrega y de quien recibe, y constancia
/// opcional de quién autorizó (texto libre). Las firmas se mandan como PNG en
/// base64 junto con la boleta; la app no sube archivos.
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

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const TarjetaSeccion(
          titulo: 'Autorización (opcional)',
          subtitulo: 'Captura el nombre de quien autorizó la entrega, si aplica.',
          child: CampoAutorizo(),
        ),
        const SizedBox(height: 12),
        TarjetaSeccion(
          titulo: 'Firmas y confirmación',
          subtitulo: 'Revisa las firmas antes de registrar la entrega.',
          child: Column(children: [
            _BloqueFirma(
              etiqueta: 'Entregado por:',
              nombre: almacenista,
              controlador: _entrega,
              alLimpiar: () => c.setFirmaEntrega(null),
            ),
            const SizedBox(height: 12),
            _BloqueFirma(
              etiqueta: e.activos.isEmpty ? 'Recibido por:' : 'Recibido por (resguardante):',
              nombre: e.recibidoPor,
              controlador: _recibe,
              alLimpiar: () => c.setFirmaRecibe(null),
              // HU8: al firmar, quien recibe queda a cargo de las herramientas prestadas.
              aviso: e.activos.isEmpty
                  ? null
                  : AvisoCaja(
                      tipo: TipoAviso.info,
                      titulo: 'Resguardo de herramientas',
                      mensaje: 'Al firmar, ${e.recibidoPor} queda como resguardante de: '
                          '${e.activos.map((a) => '${a.activo.codigo} ${a.activo.equipo}').join(', ')}. '
                          'Es responsable de devolverlas en la fecha prevista.',
                    ),
            ),
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
    this.aviso,
  });

  final String etiqueta;
  final String nombre;
  final SignatureController controlador;
  final VoidCallback alLimpiar;
  final Widget? aviso; // se muestra antes del área de firma

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
        if (aviso != null) ...[const SizedBox(height: 12), aviso!],
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
