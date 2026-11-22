import 'package:almacen_itson/core/widgets/componentes.dart';
import 'package:almacen_itson/features/ventanilla/datos/dias_prestamo.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/ventanilla_entrega_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/ventanilla_repositorio_api_test.dart' show ActivosFalso;
import 'seleccion_activos_test.dart' show abrirActivos;

// HU8 · Captura de días de préstamo con la fecha prevista de devolución: contador,
// fecha que se recalcula y validación que impide continuar.

// "Hoy" fijo: 19/11/2026, 11:00 en Hermosillo.
final _hoy = DateTime.utc(2026, 11, 19, 18);
final _reloj = relojProvider.overrideWithValue(() => _hoy);

// El campo numérico de días (no el buscador).
final campoDias = find.descendant(of: find.byType(ContadorCompacto), matching: find.byType(TextField));
final menos = find.byTooltip('Disminuir días de Taladro inalámbrico');
final mas = find.byTooltip('Aumentar días de Taladro inalámbrico');

Future<ProviderContainer> conTaladro(WidgetTester tester) async {
  final c = await abrirActivos(tester, ActivosFalso(), overrides: [_reloj]);
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  return c;
}

int dias(ProviderContainer c) => c.read(entregaControllerProvider).activos.single.dias;
String textoDelCampo(WidgetTester tester) => tester.widget<TextField>(campoDias).controller!.text;

void main() {
  group('fecha prevista de devolución', () {
    testWidgets('se muestra junto a los días con el valor por defecto (1 día)', (tester) async {
      await conTaladro(tester);

      expect(textoDelCampo(tester), '1');
      expect(find.text('Devolución prevista: 20/11/2026'), findsOneWidget);
    });

    testWidgets('se recalcula con los botones + y -', (tester) async {
      final c = await conTaladro(tester);

      await tester.tap(mas);
      await tester.pump();
      expect(dias(c), 2);
      expect(textoDelCampo(tester), '2');
      expect(find.text('Devolución prevista: 21/11/2026'), findsOneWidget);

      await tester.tap(menos);
      await tester.pump();
      expect(find.text('Devolución prevista: 20/11/2026'), findsOneWidget);
    });

    testWidgets('se recalcula al escribir los días', (tester) async {
      final c = await conTaladro(tester);

      await tester.enterText(campoDias, '10');
      await tester.pump();

      expect(dias(c), 10);
      expect(find.text('Devolución prevista: 29/11/2026'), findsOneWidget);
    });

    testWidgets('también se ve en el diálogo "Materiales a entregar"', (tester) async {
      final c = await conTaladro(tester);

      await tester.tap(find.text('Materiales a entregar'));
      await tester.pump(const Duration(milliseconds: 500));
      final enDialogo = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      expect(enDialogo, findsOneWidget);

      await tester.enterText(enDialogo, '3');
      await tester.pump();

      expect(dias(c), 3);
      expect(
          find.descendant(
              of: find.byType(Dialog),
              matching: find.text('Devolución prevista: 22/11/2026')),
          findsOneWidget);
    });
  });

  group('contador de días', () {
    testWidgets('"-" queda deshabilitado en 1 día', (tester) async {
      final c = await conTaladro(tester);

      await tester.tap(menos, warnIfMissed: false);
      await tester.pump();

      expect(dias(c), 1);
    });

    testWidgets('"+" sube hasta 30 y ahí se detiene', (tester) async {
      final c = await conTaladro(tester);
      await tester.enterText(campoDias, '30');
      await tester.pump();

      await tester.tap(mas, warnIfMissed: false);
      await tester.pump();

      expect(dias(c), 30);
      expect(find.text('Devolución prevista: 19/12/2026'), findsOneWidget);
    });

    testWidgets('escribir más de 30 lo deja en 30', (tester) async {
      final c = await conTaladro(tester);

      await tester.enterText(campoDias, '999');
      await tester.pump();

      expect(dias(c), 30);
      expect(textoDelCampo(tester), '30');
    });

    testWidgets('solo acepta dígitos', (tester) async {
      final c = await conTaladro(tester);

      await tester.enterText(campoDias, '1a2-');
      await tester.pump();

      expect(dias(c), 12);
      expect(textoDelCampo(tester), '12');
    });
  });

  group('validación de los días', () {
    testWidgets('con el campo vacío se avisa y no hay fecha', (tester) async {
      final c = await conTaladro(tester);

      await tester.enterText(campoDias, '');
      await tester.pump();

      expect(dias(c), 0);
      expect(find.text(mensajeDiasInvalidos), findsOneWidget);
      expect(find.textContaining('Devolución prevista'), findsNothing);
      expect(textoDelCampo(tester), ''); // no se rellena solo mientras se escribe
    });

    testWidgets('con 0 días se avisa; al corregirlo desaparece el aviso', (tester) async {
      final c = await conTaladro(tester);

      await tester.enterText(campoDias, '0');
      await tester.pump();
      expect(dias(c), 0);
      expect(find.text(mensajeDiasInvalidos), findsOneWidget);
      expect(textoDelCampo(tester), '0');

      await tester.enterText(campoDias, '4');
      await tester.pump();
      expect(dias(c), 4);
      expect(find.text(mensajeDiasInvalidos), findsNothing);
      expect(find.text('Devolución prevista: 23/11/2026'), findsOneWidget);
    });

    testWidgets('desde 0 el botón "+" pone 1 día', (tester) async {
      final c = await conTaladro(tester);
      await tester.enterText(campoDias, '');
      await tester.pump();

      await tester.tap(mas);
      await tester.pump();

      expect(dias(c), 1);
      expect(textoDelCampo(tester), '1');
    });
  });

  group('no permite continuar con días inválidos', () {
    FilledButton siguiente(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Siguiente'));

    testWidgets('"Siguiente" se deshabilita y se explica por qué', (tester) async {
      tester.view.physicalSize = const Size(1200, 1920);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [_reloj]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: VentanillaEntregaPage())));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Paso 1 -> paso 2 (materiales y equipo) con una herramienta.
      final n = c.read(entregaControllerProvider.notifier);
      n.seleccionarSolicitante(const Solicitante(
          id: '1', nombre: 'Pedro', dependencia: 'SG', tipo: 'ITSON', zona: 'Taller'));
      n.avanzar();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('Activos'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.byType(Checkbox).first);
      // Antes de agregarla se valida con el servidor (HU8).
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(siguiente(tester).onPressed, isNotNull);
      expect(find.text(mensajeDiasInvalidos), findsNothing);

      await tester.enterText(campoDias, '');
      await tester.pump();
      expect(siguiente(tester).onPressed, isNull);
      // Junto al campo y sobre los botones de navegación.
      expect(find.text(mensajeDiasInvalidos), findsNWidgets(2));

      await tester.enterText(campoDias, '2');
      await tester.pump();
      expect(siguiente(tester).onPressed, isNotNull);
      expect(find.text(mensajeDiasInvalidos), findsNothing);

      await tester.pump(const Duration(seconds: 1));
    });
  });
}
