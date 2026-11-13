import 'package:go_router/go_router.dart';

import 'login_page.dart';

/// Rutas del feature. La protección por sesión vive en la redirección global
/// del router (app.dart).
final rutasAutenticacion = <GoRoute>[
  GoRoute(
    path: '/login',
    builder: (context, state) => const LoginPage(),
  ),
];
