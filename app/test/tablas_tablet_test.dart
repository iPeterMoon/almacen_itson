import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_materiales.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_revision.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_solicitante.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tableta de 1200 x 1920 píxeles usada en vertical. Se prueba con factor 1.0 (ancho lógico 1200)
/// y con 1.5 (ancho lógico 800, igual que el prototipo).
/// El factor 2.0 equivale a 600 px lógicos de ancho (dispositivos más angostos, como una XP-Pen).
const _casos = <String, double>{'factor 1.0': 1.0, 'factor 1.5': 1.5, 'factor 2.0': 2.0};

Widget _app(ProviderContainer c, Widget hijo) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: hijo),
        ),
      ),
    );

/// Ninguna tabla debe tener desplazamiento horizontal: se ven completas.
void _sinScrollHorizontal(WidgetTester tester) {
  final f = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal);
  for (final s in tester.stateList<ScrollableState>(f)) {
    expect(s.position.maxScrollExtent, 0, reason: 'la tabla se desborda horizontalmente');
  }
}

void _dentroDePantalla(WidgetTester tester, Finder f) {
  final ancho = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (var i = 0; i < f.evaluate().length; i++) {
    expect(tester.getTopRight(f.at(i)).dx, lessThanOrEqualTo(ancho));
  }
}

void main() {
  for (final caso in _casos.entries) {
    group('Tableta 1200x1920 vertical (${caso.key})', () {
      void configurar(WidgetTester tester) {
        tester.view.physicalSize = const Size(1200, 1920);
        tester.view.devicePixelRatio = caso.value;
        addTearDown(tester.view.reset);
      }

      testWidgets('tabla de solicitantes completa', (tester) async {
        configurar(tester);
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c, const PasoSolicitante()));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text('Zona'), findsOneWidget);
        _dentroDePantalla(tester, find.text('Zona'));
        _sinScrollHorizontal(tester);
      });

      testWidgets('tabla de materiales y paginación completas', (tester) async {
        configurar(tester);
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(_app(c, const PasoMateriales()));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text('Existencia'), findsOneWidget);
        _dentroDePantalla(tester, find.text('Existencia'));
        _dentroDePantalla(tester, find.text('Siguiente'));
        _sinScrollHorizontal(tester);
      });

      testWidgets('tablas de revisión (materiales y activos) completas', (tester) async {
        configurar(tester);
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(entregaControllerProvider.notifier);
        final repo = VentanillaRepositorioSimulado();
        final m = (await tester.runAsync(() => repo.buscarMateriales(consulta: 'Guantes')))!.items.first;
        await tester.runAsync(() => n.agregarMaterial(material: m, cantidad: 1, unidad: 'Piezas'));
        final a = (await tester.runAsync(() => repo.buscarActivos('')))!.first;
        n.agregarActivo(a);
        // Con comentario el botón muestra un indicador: no debe desbordarse ("overflowed by 15 pixels").
        n.comentarMaterial(m.codigo, 'Prueba');
        n.comentarActivo(a.codigo, 'Prueba');

        await tester.pumpWidget(_app(c, const PasoRevision()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Acciones'), findsNWidgets(2));
        _dentroDePantalla(tester, find.text('Acciones'));
        _sinScrollHorizontal(tester);
      });
    });
  }
}
