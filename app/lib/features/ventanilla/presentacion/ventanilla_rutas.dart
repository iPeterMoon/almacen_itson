import 'package:go_router/go_router.dart';

import 'ventanilla_entrega_page.dart';

/// Rutas del feature. Agregar `rutasVentanilla` al GoRouter principal (app.dart).
/// Debe quedar protegida por rol (almacenista) en la redirección global.
final rutasVentanilla = <GoRoute>[
  GoRoute(
    path: '/ventanilla/nueva-entrega',
    builder: (context, state) => const VentanillaEntregaPage(),
  ),
];
