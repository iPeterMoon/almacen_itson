import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/tema/tema.dart';
import 'features/autenticacion/presentacion/autenticacion_rutas.dart';
import 'features/autenticacion/presentacion/sesion_controlador.dart';
import 'features/ventanilla/presentacion/ventanilla_rutas.dart';

class _AvisoSesion extends ChangeNotifier {
  void avisar() => notifyListeners();
}

// El router escucha la sesión: sin sesión solo se puede ver /login; al iniciar
// sesión se entra a la pantalla principal. Los tokens se restauran al arrancar.
final proveedorRouter = Provider<GoRouter>((ref) {
  final aviso = _AvisoSesion();
  ref.listen(controladorSesionProvider, (_, _) => aviso.avisar());
  ref.onDispose(aviso.dispose);

  final router = GoRouter(
    initialLocation: '/login',
    refreshListenable: aviso,
    redirect: (context, state) {
      final sesion = ref.read(controladorSesionProvider);
      final enLogin = state.matchedLocation == '/login';

      // Mientras se lee la sesión guardada se mantiene el login; cuando
      // termina, esta misma redirección decide si entra o se queda ahí.
      if (sesion.isLoading) return enLogin ? null : '/login';

      final autenticado = sesion.value != null;
      if (!autenticado) return enLogin ? null : '/login';
      if (enLogin) return '/';
      return null;
    },
    routes: [
      ...rutasAutenticacion,
      ...rutasVentanilla,
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Almacenes ITSON',
      theme: Tema.claro(),
      routerConfig: ref.watch(proveedorRouter),
      debugShowCheckedModeBanner: false,
    );
  }
}
