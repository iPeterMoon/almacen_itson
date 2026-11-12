import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_confirmacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la persona elegida en "Autorizó" aparece en la pantalla de firmas', (tester) async {
    tester.view.physicalSize = const Size(1200, 1920);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    contenedor.read(entregaControllerProvider.notifier).setAutorizo('a1'); // Leonel Lares

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoConfirmacion())),
    ));
    await tester.pump(const Duration(seconds: 1)); // carga la lista de autorizadores

    expect(find.text('Autorizado por'), findsOneWidget);
    expect(find.text('Leonel Lares'), findsOneWidget);
  });

  testWidgets('sin autorizador no se muestra el bloque "Autorizado por"', (tester) async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoConfirmacion())),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Autorizado por'), findsNothing);
  });
}
