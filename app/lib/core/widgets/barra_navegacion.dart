import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Secciones principales de la app, en el orden de la barra inferior del Figma.
enum SeccionApp {
  reportes('Reportes', Icons.grid_view_outlined),
  prestamos('Préstamos', Icons.home_repair_service_outlined),
  ventanilla('Ventanilla', Icons.assignment_outlined),
  inventario('Inventario', Icons.inventory_2_outlined),
  personalZonas('Personal y Zonas', Icons.people_outline),
  movimientos('Movimientos', Icons.visibility_outlined);

  const SeccionApp(this.etiqueta, this.icono);
  final String etiqueta;
  final IconData icono;
}

/// Barra de navegación inferior. La sección actual se resalta con un fondo azul claro.
/// Por ahora solo existe Ventanilla: las demás secciones no hacen nada al tocarlas
/// hasta que tengan pantalla y ruta.
class BarraNavegacionInferior extends StatelessWidget {
  const BarraNavegacionInferior({super.key, required this.actual, this.onSeleccionar});

  final SeccionApp actual;
  final ValueChanged<SeccionApp>? onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colores.borde)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            for (final s in SeccionApp.values)
              Expanded(child: _Opcion(seccion: s, seleccionada: s == actual, onTap: onSeleccionar)),
          ]),
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.seccion, required this.seleccionada, required this.onTap});

  final SeccionApp seccion;
  final bool seleccionada;
  final ValueChanged<SeccionApp>? onTap;

  @override
  Widget build(BuildContext context) {
    final color = seleccionada ? Colores.primario : Colores.textoSuave;
    return Semantics(
      button: true,
      selected: seleccionada,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: seleccionada ? Colores.navegacionActual : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap?.call(seccion),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(seccion.icono, color: color),
                const SizedBox(height: 6),
                Text(seccion.etiqueta,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: 12.5, color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
