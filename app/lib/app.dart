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

/// Pantalla principal después de iniciar sesión: la ventanilla de entregas.
/// Conserva el botón "+ Nueva entrega" original y agrega el cierre de sesión.
class _PantallaInicio extends ConsumerWidget {
  const _PantallaInicio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventanilla de entregas'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(controladorSesionProvider.notifier).cerrarSesion(),
            icon: const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/ventanilla/nueva-entrega'),
          child: const Text('+ Nueva entrega'),
        ),
      ),
    );
  }
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

      // Mientras se lee la sesión guardada no se expulsa al usuario.
      if (sesion.isLoading) return enLogin ? null : '/login';

      final autenticado = sesion.value != null;
      if (!autenticado) return enLogin ? null : '/login';
      if (enLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _PantallaInicio()),
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
