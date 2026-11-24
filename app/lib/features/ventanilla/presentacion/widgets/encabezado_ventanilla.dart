import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../autenticacion/presentacion/sesion_controlador.dart';

/// Encabezado común de todas las pantallas de Ventanilla (Figma): título,
/// subtítulo, notificaciones y cierre de sesión.
class EncabezadoVentanilla extends ConsumerWidget implements PreferredSizeWidget {
  const EncabezadoVentanilla({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight: 72,
      titleSpacing: 16,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ventanilla de entregas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
          Text('Entrega de material y equipo',
              style: TextStyle(fontSize: 13, color: Colores.textoSuave)),
        ],
      ),
      actions: [
        _BotonEncabezado(
          tooltip: 'Notificaciones',
          icono: Icons.notifications_none_outlined,
          // Pendiente: la sección de alertas aún no existe (feature alertas/).
          onPressed: () {},
        ),
        const SizedBox(width: 12),
        _BotonEncabezado(
          tooltip: 'Cerrar sesión',
          icono: Icons.logout_outlined,
          onPressed: () => ref.read(controladorSesionProvider.notifier).cerrarSesion(),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

/// Botón cuadrado con borde, como los del encabezado del Figma.
class _BotonEncabezado extends StatelessWidget {
  const _BotonEncabezado({required this.tooltip, required this.icono, required this.onPressed});

  final String tooltip;
  final IconData icono;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icono, color: Colores.textoEtiqueta),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Colores.bordeCampo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
