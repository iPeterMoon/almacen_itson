import 'package:almacen_itson/features/autenticacion/datos/supervisores_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/dialogos/dialogo_stock_y_resumen.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_confirmacion.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// HU8: las herramientas prestadas en la revisión, las firmas y el resumen de la boleta,
// tanto en una boleta solo de herramientas como en una combinada con material (E6).

const _taladro = ActivoCatalogo(
  codigo: 'ACT-104',
  equipo: 'Taladro percutor',
  modelo: 'GBH 2-28',
  serie: 'SN-77821',
  almacen: 'Mantenimiento',
  ubicacion: 'Estante 1',
  activoId: 104,
);

const _pinol = MaterialCatalogo(
  codigo: 'CD-123',
  concepto: 'Limpiador multiusos',
  alias: 'Pinol',
  categoria: 'Líquido',
  tipo: 'Servicios Generales',
  almacen: 'Dormitorios',
  ubicacion: 'Estante 2',
  existencia: 12,
  unidadBase: 'L',
  unidades: ['L'],
);

const _juan = Solicitante(
  id: '1',
  nombre: 'Juan Pérez Soto',
  dependencia: 'Servicios Generales',
  tipo: 'ITSON',
  zona: 'Taller Principal',
);

// 18:00 UTC del 20/11/2026 = 11:00 a.m. en Hermosillo.
final _ahora = DateTime.utc(2026, 11, 20, 18);

const _lineaTaladro = LineaHerramientaResumen(
  codigo: 'ACT-104',
  nombre: 'Taladro percutor',
  modelo: 'GBH 2-28',
  serie: 'SN-77821',
  dias: 3,
  folioPrestamo: 'PRE-2026-0008',
  fechaPrevista: '23/11/2026',
);

ResumenEntrega _resumen({
  List<LineaResumen> materiales = const [],
  List<LineaHerramientaResumen> herramientas = const [_lineaTaladro],
}) =>
    ResumenEntrega(
      folio: 'BOL-2026-000012',
      recibidoPor: 'Juan Pérez Soto',
      area: 'Servicios Generales',
      fechaHora: '11:00 a.m. 20/11/2026',
      entregadoPor: 'Alicia García',
      materiales: materiales,
      herramientas: herramientas,
    );

/// Contenedor con el solicitante elegido, el taladro por 3 días y, si [conMaterial],
/// también material en la misma boleta.
ProviderContainer _boleta({bool conMaterial = false}) {
  final contenedor = ProviderContainer(overrides: [
    relojProvider.overrideWithValue(() => _ahora),
    supervisoresProvider.overrideWithValue(AsyncValue.data(<Supervisor>[])),
  ]);
  final c = contenedor.read(entregaControllerProvider.notifier)
    ..seleccionarSolicitante(_juan)
    ..agregarActivo(_taladro)
    ..cambiarDias('ACT-104', 3);
  if (conMaterial) {
    c.agregarMaterialConMotivo(
      material: _pinol,
      cantidad: 2,
      unidad: 'L',
      motivoExcepcion: const MotivoExcepcion(motivo: 'Emergencia'),
    );
  }
  return contenedor;
}

Future<void> _pintar(WidgetTester tester, ProviderContainer contenedor, Widget paso) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(contenedor.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: contenedor,
    child: MaterialApp(home: Scaffold(body: paso)),
  ));
  await tester.pump();
}

Future<void> _abrirResumen(WidgetTester tester, ResumenEntrega r) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => mostrarDialogoResumen(context, r),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('boleta solo de herramientas', () {
    testWidgets('la revisión muestra código, nombre, modelo, serie, días y fecha prevista',
        (tester) async {
      await _pintar(tester, _boleta(), const PasoRevision());

      expect(find.text('Herramientas (préstamo)'), findsOneWidget);
      expect(find.text('Taladro percutor'), findsOneWidget);
      expect(find.text('ACT-104'), findsOneWidget);
      expect(find.text('GBH 2-28'), findsOneWidget);
      expect(find.text('SN-77821'), findsOneWidget);
      expect(find.text('3 día(s)'), findsOneWidget);
      expect(find.text('23/11/2026'), findsOneWidget);
      // Sin materiales no se muestra una sección vacía.
      expect(find.text('Materiales (entrega)'), findsNothing);
    });

    testWidgets('en las firmas, quien recibe queda como resguardante', (tester) async {
      await _pintar(tester, _boleta(), const PasoConfirmacion());

      expect(find.text('Recibido por (resguardante):'), findsOneWidget);
      expect(find.text('Resguardo de herramientas'), findsOneWidget);
      expect(find.textContaining('Juan Pérez Soto queda como resguardante de: ACT-104'),
          findsOneWidget);
    });

    testWidgets('el resumen muestra el folio BOL-, el folio PRE- y la fecha prevista',
        (tester) async {
      await _abrirResumen(tester, _resumen());

      expect(find.text('Folio BOL-2026-000012'), findsOneWidget);
      expect(find.text('Herramientas en préstamo'), findsOneWidget);
      expect(find.text('Resguardante: Juan Pérez Soto'), findsOneWidget);
      expect(find.text('PRE-2026-0008'), findsOneWidget);
      expect(find.text('23/11/2026'), findsOneWidget);
      expect(find.text('Materiales entregados'), findsNothing);
    });

    testWidgets('si el servidor no manda el folio de préstamo se muestra "Sin folio"', (tester) async {
      const sinFolio = LineaHerramientaResumen(
        codigo: 'ACT-104',
        nombre: 'Taladro percutor',
        modelo: 'GBH 2-28',
        serie: 'SN-77821',
        dias: 3,
        fechaPrevista: '23/11/2026',
      );
      await _abrirResumen(tester, _resumen(herramientas: const [sinFolio]));

      expect(find.text('Sin folio'), findsOneWidget);
    });
  });

  group('boleta combinada con material (E6)', () {
    testWidgets('la revisión separa materiales y herramientas', (tester) async {
      await _pintar(tester, _boleta(conMaterial: true), const PasoRevision());

      expect(find.text('Materiales (entrega)'), findsOneWidget);
      expect(find.text('Herramientas (préstamo)'), findsOneWidget);
      expect(find.text('Pinol'), findsOneWidget);
      expect(find.text('2 L'), findsOneWidget);
      expect(find.text('ACT-104'), findsOneWidget);
      expect(find.text('23/11/2026'), findsOneWidget);
    });

    testWidgets('las firmas son las mismas y marcan al resguardante', (tester) async {
      await _pintar(tester, _boleta(conMaterial: true), const PasoConfirmacion());

      expect(find.text('Entregado por:'), findsOneWidget);
      expect(find.text('Recibido por (resguardante):'), findsOneWidget);
    });

    testWidgets('el resumen muestra materiales y herramientas en secciones separadas',
        (tester) async {
      await _abrirResumen(
        tester,
        _resumen(materiales: const [LineaResumen('CD-123', 'Pinol', '2 L')]),
      );

      expect(find.text('Folio BOL-2026-000012'), findsOneWidget);
      expect(find.text('Materiales entregados'), findsOneWidget);
      expect(find.text('Pinol'), findsOneWidget);
      expect(find.text('Herramientas en préstamo'), findsOneWidget);
      expect(find.text('PRE-2026-0008'), findsOneWidget);
      // La sección de materiales va antes que la de herramientas.
      expect(
        tester.getTopLeft(find.text('Materiales entregados')).dy,
        lessThan(tester.getTopLeft(find.text('Herramientas en préstamo')).dy),
      );
    });
  });

  testWidgets('una boleta solo de materiales no marca resguardante', (tester) async {
    final contenedor = ProviderContainer(overrides: [
      supervisoresProvider.overrideWithValue(AsyncValue.data(<Supervisor>[])),
    ]);
    contenedor.read(entregaControllerProvider.notifier).seleccionarSolicitante(_juan);
    await _pintar(tester, contenedor, const PasoConfirmacion());

    expect(find.text('Recibido por:'), findsOneWidget);
    expect(find.text('Resguardo de herramientas'), findsNothing);
  });
}
