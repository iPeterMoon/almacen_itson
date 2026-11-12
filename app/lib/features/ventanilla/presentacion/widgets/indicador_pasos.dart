import 'package:flutter/material.dart';
import '../../../../core/tema/tema.dart';

/// Indicador de 4 pasos del Figma: verde = completado, azul = actual, gris = pendiente.
class IndicadorPasos extends StatelessWidget {
  const IndicadorPasos({super.key, required this.actual});
  final int actual; // 0..3

  static const _etiquetas = ['Solicitante', 'Materiales', 'Revisión', 'Confirmación'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colores.borde),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Semantics(
                label: 'Paso ${i + 1}: ${_etiquetas[i]}',
                child: Column(children: [
                  Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i < actual
                          ? Colores.exito
                          : i == actual
                              ? Colores.primario
                              : Colores.borde,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: i < actual
                        ? Colores.exitoFondo
                        : i == actual
                            ? Colores.primario
                            : Colores.fondo,
                    child: Text('${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: i < actual
                              ? Colores.exitoOscuro
                              : i == actual
                                  ? Colors.white
                                  : Colores.textoSuave,
                        )),
                  ),
                  const SizedBox(height: 4),
                  Text(_etiquetas[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: i < actual
                            ? Colores.exitoOscuro
                            : i == actual
                                ? Colores.primario
                                : Colores.textoSuave,
                      )),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
