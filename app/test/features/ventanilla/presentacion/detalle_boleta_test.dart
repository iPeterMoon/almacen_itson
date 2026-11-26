import 'dart:async';

import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/detalle_boleta.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/dialogos/dialogo_detalle_boleta.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_page.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/ventanilla_rutas.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/seleccion_activos.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// La boleta del Figma: 4 materiales, 2 herramientas en préstamo y autorizada.
const _materiales = [
  MaterialDeBoleta(
      codigo: 'CD-123',
      concepto: 'Limpiador multiusos (Pinol)',
      almacen: 'Servicios generales',
      presentacion: 'L',
      cantidad: 10),
  MaterialDeBoleta(
      codigo: 'CD-987',
      concepto: 'Pintura epóxica',
      almacen: 'Mantenimiento',
      presentacion: 'L',
      cantidad: 0.5),
];

const _herramientas = [
  HerramientaDeBoleta(
      codigo: '912398',
      nombre: 'Rotomartillo',
      modelo: 'DCF997D2',
      numeroSerie: '2023351982',
      estado: 'EN_PRESTAMO'),
  HerramientaDeBoleta(
      codigo: '231239',
      nombre: 'Podadora Truper',
      modelo: 'DCF27889',
      numeroSerie: '2131239823',
      estado: 'DISPONIBLE'),
];

DetalleBoleta _boleta({
  List<HerramientaDeBoleta> herramientas = _herramientas,
  String? autorizoNombre = 'Carlos Mendoza Ruiz',
}) =>
    DetalleBoleta(
      id: 184,
      folio: 'ENT-2026-0184',
      solicitante: 'Juan Pérez Soto',
      dependencia: 'Mantenimiento',
      unidad: 'Obregón',
      campus: 'Náinari',
      entregadoEn: '2026-10-17T16:35:00Z', // 09:35 a.m. en Hermosillo
      entregadoPor: 'Ana Lucía Torres',
      autorizoNombre: autorizoNombre,
      materiales: _materiales,
      herramientas: herramientas,
    );

class _RepoFalso extends HistorialEntregasRepositorio {
  _RepoFalso({this.boleta, this.error, this.espera}) : super(Dio());

  final DetalleBoleta? boleta;
  ErrorNegocio? error;
  final Completer<void>? espera;
  final List<int> detallesPedidos = [];

  @override
  Future<Pagina<EntregaHistorial>> listar({
    required int pagina,
    required int porPagina,
    String consulta = '',
  }) async =>
      const Pagina(
        items: [
          EntregaHistorial(id: 184, folio: 'ENT-2026-0184', solicitante: 'Juan Pérez Soto'),
          EntregaHistorial(id: 183, folio: 'ENT-2026-0183', solicitante: 'Marisol Duarte Cota'),
        ],
        total: 2,
        pagina: 1,
        porPagina: 9,
      );

  @override
  Future<DetalleBoleta> detalle(int boletaId) async {
    detallesPedidos.add(boletaId);
    if (espera != null) await espera!.future;
    if (error != null) throw error!;
    return boleta ?? _boleta();
  }
}

// Abre el historial y toca la fila de la boleta 184.
Future<void> _abrirDetalle(WidgetTester tester, _RepoFalso repo, {bool esperar = true}) async {
  // Tableta en vertical, ancho lógico de 800 como el prototipo.
  tester.view.physicalSize = const Size(1200, 1920);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(retry: reintentoProveedores, overrides: [
    proveedorHistorialEntregasRepositorio.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  final router = GoRouter(initialLocation: rutaHistorialEntregas, routes: rutasVentanilla);
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('ENT-2026-0184'));
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder _enDialogo(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

void main() {
  testWidgets('al tocar una fila del historial abre el detalle de esa boleta con sus datos generales',
      (tester) async {
    final repo = _RepoFalso();
    await _abrirDetalle(tester, repo);

    expect(repo.detallesPedidos, [184]);
    expect(find.byType(DialogoDetalleBoleta), findsOneWidget);
    expect(find.text('Detalles de entrega'), findsOneWidget);
    expect(find.text('Folio ENT-2026-0184'), findsOneWidget);
    for (final (etiqueta, valor) in [
      ('Solicitante', 'Juan Pérez Soto'),
      ('Dependencia', 'Mantenimiento'),
      ('Entregada por', 'Ana Lucía Torres'),
      ('Fecha y hora', '17/10/2026 09:35 a.m.'),
      ('Unidad', 'Obregón'),
      ('Campus', 'Náinari'),
    ]) {
      expect(find.text('$etiqueta: $valor', findRichText: true), findsOneWidget);
    }

    // Tabla de materiales con la cantidad y su presentación.
    expect(find.text('Materiales'), findsOneWidget);
    for (final columna in DialogoDetalleBoleta.encabezadosMateriales) {
      expect(_enDialogo(find.text(columna)), findsOneWidget);
    }
    expect(find.text('Limpiador multiusos (Pinol)'), findsOneWidget);
    expect(find.text('Servicios generales'), findsOneWidget);
    expect(find.text('10 L'), findsOneWidget);
    expect(find.text('0.5 L'), findsOneWidget);
  });

  testWidgets('con herramientas muestra la tabla de préstamos con el estado actual de cada una',
      (tester) async {
    await _abrirDetalle(tester, _RepoFalso());

    expect(_enDialogo(find.text('Préstamos')), findsOneWidget);
    for (final columna in DialogoDetalleBoleta.encabezadosPrestamos) {
      expect(find.text(columna), findsOneWidget);
    }
    expect(find.text('Rotomartillo'), findsOneWidget);
    expect(find.text('DCF27889'), findsOneWidget);
    expect(find.text('2023351982'), findsOneWidget);
    // El estado va como etiqueta de color, con su texto.
    expect(find.byType(EtiquetaEstadoActivo), findsNWidgets(2));
    expect(find.widgetWithText(EtiquetaEstadoActivo, 'En préstamo'), findsOneWidget);
    expect(find.widgetWithText(EtiquetaEstadoActivo, 'Disponible'), findsOneWidget);
  });

  testWidgets('sin herramientas se oculta la tabla de préstamos', (tester) async {
    await _abrirDetalle(tester, _RepoFalso(boleta: _boleta(herramientas: const [])));

    expect(_enDialogo(find.text('Préstamos')), findsNothing);
    expect(find.text('Código activo'), findsNothing);
    expect(find.byType(EtiquetaEstadoActivo), findsNothing);
    expect(find.text('Materiales'), findsOneWidget);
  });

  testWidgets('con autorización muestra quién autorizó y cuándo', (tester) async {
    await _abrirDetalle(tester, _RepoFalso());

    expect(
        find.text('Autorizada por Carlos Mendoza Ruiz · 17/10/2026 09:35 a.m.',
            findRichText: true),
        findsOneWidget);
  });

  testWidgets('sin autorización no muestra el bloque de autorización', (tester) async {
    await _abrirDetalle(tester, _RepoFalso(boleta: _boleta(autorizoNombre: null)));

    expect(find.textContaining('Autorizada por', findRichText: true), findsNothing);
    expect(find.text('Folio ENT-2026-0184'), findsOneWidget);
  });

  testWidgets('un nombre de autorización vacío cuenta como sin autorización', (tester) async {
    await _abrirDetalle(tester, _RepoFalso(boleta: _boleta(autorizoNombre: '  ')));

    expect(find.textContaining('Autorizada por', findRichText: true), findsNothing);
  });

  testWidgets('mientras carga muestra el indicador de carga', (tester) async {
    final espera = Completer<void>();
    await _abrirDetalle(tester, _RepoFalso(espera: espera), esperar: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(_enDialogo(find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(find.text('Folio ENT-2026-0184'), findsNothing);

    espera.complete();
    await tester.pumpAndSettle();
    expect(find.text('Folio ENT-2026-0184'), findsOneWidget);
  });

  testWidgets('un error muestra el mensaje del servidor y permite reintentar', (tester) async {
    final repo = _RepoFalso(
        error: const ErrorNegocio('BOLETA_NO_EXISTE', 'La boleta 184 no existe.'));
    await _abrirDetalle(tester, repo);

    expect(find.text('La boleta 184 no existe.'), findsOneWidget);
    expect(find.text('Folio ENT-2026-0184'), findsNothing);

    repo.error = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(repo.detallesPedidos, [184, 184]);
    expect(find.text('Folio ENT-2026-0184'), findsOneWidget);
  });

  testWidgets('"Cerrar" regresa al historial', (tester) async {
    await _abrirDetalle(tester, _RepoFalso());

    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar'));
    await tester.pumpAndSettle();

    expect(find.byType(DialogoDetalleBoleta), findsNothing);
    expect(find.byType(HistorialEntregasPage), findsOneWidget);
  });

  testWidgets('cada apertura vuelve a consultar el detalle', (tester) async {
    final repo = _RepoFalso();
    await _abrirDetalle(tester, repo);
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ENT-2026-0183'));
    await tester.pumpAndSettle();

    expect(repo.detallesPedidos, [184, 183]);
  });
}
