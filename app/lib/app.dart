import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/tema/tema.dart';
import 'features/ventanilla/presentacion/ventanilla_rutas.dart';

/// App mínima para probar la HU6. En el proyecto real, el router lo comparte todo el equipo.
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Ventanilla de entregas')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/ventanilla/nueva-entrega'),
            child: const Text('+ Nueva entrega'),
          ),
        ),
      ),
    ),
    ...rutasVentanilla,
  ],
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Almacenes ITSON',
        theme: Tema.claro(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      );
}
