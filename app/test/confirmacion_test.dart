import 'package:almacen_itson/features/autenticacion/datos/supervisores_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_confirmacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('el campo "Autorizó" aparece en las firmas con el nombre capturado', (tester) async {
    tester.view.physicalSize = const Size(1200, 1920);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    final contenedor = ProviderContainer(overrides: [
      supervisoresProvider.overrideWithValue(AsyncValue.data(<Supervisor>[])),
    ]);
    addTearDown(contenedor.dispose);
    contenedor.read(entregaControllerProvider.notifier).setAutorizoNombre('Supervisor externo');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoConfirmacion())),
    ));
    await tester.pump();

    expect(find.text('Autorizó (Opcional)'), findsOneWidget);
    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.controller!.text, 'Supervisor externo');
  });

  testWidgets('sin nombre en "Autorizó" el campo aparece vacío', (tester) async {
    final contenedor = ProviderContainer(overrides: [
      supervisoresProvider.overrideWithValue(AsyncValue.data(<Supervisor>[])),
    ]);
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoConfirmacion())),
    ));
    await tester.pump();

    expect(find.text('Autorizó (Opcional)'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('el campo "Autorizó" ignora números y signos', (tester) async {
    final contenedor = ProviderContainer(overrides: [
      supervisoresProvider.overrideWithValue(AsyncValue.data(<Supervisor>[])),
    ]);
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoConfirmacion())),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Ana 123-#');
    final texto = tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(texto.replaceAll(' ', ''), 'Ana');
    expect(texto.contains(RegExp(r'[0-9#-]')), isFalse);
    expect(contenedor.read(entregaControllerProvider).autorizoNombre.replaceAll(' ', ''), 'Ana');
  });
}
