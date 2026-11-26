import 'package:flutter/material.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/importacion_entregas_repositorio.dart';

/// HU11 (escenario 6): lista de fila y motivo cuando el Excel trae errores.
Future<void> mostrarDialogoErroresImportacion(
  BuildContext context,
  List<ErrorFilaImportacion> errores,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No se importó ninguna boleta',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              AvisoCaja(
                tipo: TipoAviso.error,
                titulo: errores.length == 1 ? '1 error' : '${errores.length} errores',
                mensaje: 'Corrige el archivo y vuelve a importarlo.',
              ),
              const SizedBox(height: 16),
              const _Fila(fila: 'Fila', motivo: 'Motivo', encabezado: true),
              // Perezosa, a diferencia de TablaDatos: un archivo de 1 000 filas puede
              // traer miles de errores.
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: errores.length,
                  itemBuilder: (_, i) => _Fila(
                    fila: '${errores[i].fila}',
                    motivo: errores[i].motivo,
                    alterna: i.isOdd,
                  ),
                ),
              ),
              const SizedBox(height: 16),
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

class _Fila extends StatelessWidget {
  const _Fila({
    required this.fila,
    required this.motivo,
    this.encabezado = false,
    this.alterna = false,
  });

  final String fila;
  final String motivo;
  final bool encabezado;
  final bool alterna;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      color: Colores.texto,
      fontWeight: encabezado ? FontWeight.w700 : FontWeight.w400,
    );
    return Container(
      color: encabezado
          ? Colores.encabezadoTabla
          : (alterna ? Colores.filaAlterna : Colors.white),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(width: 72, child: Text(fila, style: estilo)),
        Expanded(child: Text(motivo, style: estilo)),
      ]),
    );
  }
}
