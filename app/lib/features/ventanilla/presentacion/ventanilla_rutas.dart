import 'package:go_router/go_router.dart';

import 'historial_entregas_page.dart';
import 'ventanilla_entrega_page.dart';

/// Pantalla principal de Ventanilla: historial de entregas (HU11).
const rutaHistorialEntregas = '/';

/// Registro de una entrega de material (HU6).
const rutaNuevaEntrega = '/ventanilla/nueva-entrega';

/// Rutas del feature. Agregar `rutasVentanilla` al GoRouter principal (app.dart).
/// Debe quedar protegida por rol (almacenista) en la redirección global.
final rutasVentanilla = <GoRoute>[
  GoRoute(
    path: rutaHistorialEntregas,
    builder: (context, state) => const HistorialEntregasPage(),
  ),
  GoRoute(
    path: rutaNuevaEntrega,
    builder: (context, state) => const VentanillaEntregaPage(),
  ),
];
