import 'package:flutter/material.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../datos/modelos.dart';

// Avisos de la HU8 al agregar una herramienta: no disponible (E3), ya prestada (E2),
// no encontrada (E4) y solicitante con préstamo vencido (E5, solo advierte).

const mensajeActivoNoEncontrado = 'Activo no encontrado';

/// Estado del activo como se lee en pantalla.
String textoEstadoActivo(String estado) => switch (estado) {
      estadoActivoDisponible => 'Disponible',
      estadoActivoEnPrestamo => 'En préstamo',
      estadoActivoEnReparacion => 'En reparación',
      estadoActivoRoboExtravio => 'Robo/Extravío',
      estadoActivoDeBaja => 'De baja',
      _ => estado,
    };

/// "912400 no está disponible (En reparación)".
String mensajeNoDisponible(String codigo, String estado) =>
    '$codigo no está disponible (${textoEstadoActivo(estado)})';

/// "912391 está prestado a Mario Acosta hasta el 19/10/2026".
String mensajePrestado(String codigo, String custodio, String fecha) =>
    '$codigo está prestado a $custodio hasta el $fecha';

/// "Juan Pérez tiene un préstamo vencido".
String mensajeVencido(String solicitante) => '$solicitante tiene un préstamo vencido';

/// Mensaje de una validación que no permite prestar el activo.
String mensajeNoPrestable(ValidacionActivo v) => v.prestado
    ? mensajePrestado(v.activo.codigo, v.custodio ?? 'otro trabajador', v.fechaPrevista ?? '-')
    : mensajeNoDisponible(v.activo.codigo, v.activo.estado);

/// Traduce los errores de activo que puede mandar el servidor (al validar o al crear
/// la boleta) a los mensajes de la HU8. Cualquier otro error se muestra tal cual.
String mensajeDeError(ErrorNegocio e) {
  switch (e.codigo) {
    case 'ACTIVO_NO_ENCONTRADO':
      return mensajeActivoNoEncontrado;
    case 'ACTIVO_PRESTADO':
      // La base ya manda "<código> está prestado a <custodio> hasta el <fecha>.".
      return _sinPuntoFinal(e.mensaje);
    case 'ACTIVO_NO_DISPONIBLE':
      // La base manda el estado crudo, ej. "912400 no está disponible (EN_REPARACION).".
      final m = RegExp(r'^(\S+) (?:ya )?no está disponible \(([A-Z_]+)\)').firstMatch(e.mensaje);
      return m == null ? _sinPuntoFinal(e.mensaje) : mensajeNoDisponible(m[1]!, m[2]!);
    default:
      return e.mensaje;
  }
}

String _sinPuntoFinal(String texto) =>
    texto.endsWith('.') ? texto.substring(0, texto.length - 1) : texto;

/// Diálogo del prototipo "Detalles de activo en préstamo" (o "Activo no disponible"):
/// dice por qué no se puede prestar y muestra la información general del activo.
Future<void> mostrarDialogoActivoNoPrestable(BuildContext context, ValidacionActivo v) {
  final a = v.activo;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                    v.prestado ? 'Detalles de activo en préstamo' : 'Activo no disponible',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 20),
              AvisoCaja(tipo: TipoAviso.error, mensaje: mensajeNoPrestable(v)),
              const SizedBox(height: 20),
              const Text('Información General', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _FilaDetalle('Valor activo', a.codigo),
              _FilaDetalle('Equipo', a.equipo),
              _FilaDetalle('Modelo', a.modelo),
              _FilaDetalle('Número de serie', a.serie),
              if (v.prestado) ...[
                _FilaDetalle('Solicitante', v.custodio ?? '-'),
                if (v.prestadoEn != null) _FilaDetalle('Fecha y hora de préstamo', v.prestadoEn!),
                _FilaDetalle('Fecha prevista de devolución', v.fechaPrevista ?? '-', ultima: true),
              ] else
                _FilaDetalle('Estado', textoEstadoActivo(a.estado), ultima: true),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FilaDetalle extends StatelessWidget {
  const _FilaDetalle(this.etiqueta, this.valor, {this.ultima = false});
  final String etiqueta;
  final String valor;
  final bool ultima;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: ultima ? null : const Border(bottom: BorderSide(color: Colores.borde)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(etiqueta,
                  style: const TextStyle(color: Colores.textoSuave, fontWeight: FontWeight.w600))),
          const SizedBox(width: 16),
          Expanded(child: Text(valor)),
        ]),
      );
}
