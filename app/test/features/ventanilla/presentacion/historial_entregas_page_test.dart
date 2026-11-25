import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/widgets/barra_navegacion.dart';
import 'package:almacen_itson/core/widgets/componentes.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_page.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/ventanilla_entrega_page.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/ventanilla_rutas.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 20 entregas, de la más reciente (folio 0020) a la más antigua (0001), como las
// ordena el servidor. Cada página devuelve su tramo.
class _RepoFalso extends HistorialEntregasRepositorio {
  _RepoFalso({this.total = 20, this.error}) : super(Dio());

  int total;
  final ErrorNegocio? error;
  final List<int> paginasPedidas = [];

  @override
  Future<Pagina<EntregaHistorial>> listar({required int pagina, required int porPagina}) async {
    paginasPedidas.add(pagina);
    if (error != null) throw error!;
    final inicio = (pagina - 1) * porPagina;
    final items = [
      for (var i = inicio; i < total && i < inicio + porPagina; i++)
        EntregaHistorial(
          id: total - i,
          folio: 'ENT-2026-${(total - i).toString().padLeft(4, '0')}',
          solicitante: 'Solicitante ${total - i}',
          dependencia: i == 0 ? null : 'Servicios Generales',
          entregadoEn: '2026-10-20T15:35:00Z',
          supervisor: i == 0 ? null : 'Carlos Mendoza Ruiz',
        ),
    ];
    return Pagina(items: items, total: total, pagina: pagina, porPagina: porPagina);
  }
}

Future<(ProviderContainer, GoRouter)> _abrir(WidgetTester tester, _RepoFalso repo) async {
  // Tableta en vertical, ancho lógico de 800 como el prototipo.
  tester.view.physicalSize = const Size(1200, 1920);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);

  // Mismos reintentos que la app: un ErrorNegocio no se reintenta solo.
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
  return (c, router);
}

void main() {
  testWidgets('muestra la tabla con las columnas del Figma, de la más reciente a la más antigua',
      (tester) async {
    final repo = _RepoFalso();
    await _abrir(tester, repo);

    expect(find.text('Historial de entregas'), findsOneWidget);
    for (final columna in HistorialEntregasPage.encabezados) {
      expect(find.text(columna), findsOneWidget);
    }
    expect(find.text('ENT-2026-0020'), findsOneWidget);
    expect(find.text('ENT-2026-0012'), findsOneWidget);
    expect(find.text('ENT-2026-0011'), findsNothing, reason: 'solo 9 filas por página');
    // Primera fila arriba: la más reciente.
    expect(tester.getTopLeft(find.text('ENT-2026-0020')).dy,
        lessThan(tester.getTopLeft(find.text('ENT-2026-0019')).dy));
    expect(find.text('Solicitante 19'), findsOneWidget);
    expect(find.text('20/10/2026 08:35 a.m.'), findsNWidgets(9));
    // Sin dependencia ni supervisor se muestra un guion.
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Mostrando 9 de 20 registros'), findsOneWidget);
    expect(repo.paginasPedidas, [1]);
  });

  testWidgets('la paginación pide la página siguiente y actualiza el total mostrado',
      (tester) async {
    final repo = _RepoFalso();
    await _abrir(tester, repo);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('ENT-2026-0011'), findsOneWidget);
    expect(find.text('ENT-2026-0020'), findsNothing);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('ENT-2026-0002'), findsOneWidget);
    expect(find.text('Mostrando 2 de 20 registros'), findsOneWidget);
    final paginador = tester.widget<PaginadorTabla>(find.byType(PaginadorTabla));
    expect(paginador.pagina, 3);
    expect(paginador.totalPaginas, 3);

    await tester.tap(find.text('Anterior'));
    await tester.pumpAndSettle();
    expect(find.text('ENT-2026-0011'), findsOneWidget);
    expect(repo.paginasPedidas, [1, 2, 3, 2]);
  });

  testWidgets('"+ Nueva entrega" abre el registro de entrega con el estado reiniciado',
      (tester) async {
    final (c, _) = await _abrir(tester, _RepoFalso());
    // Restos de una boleta anterior que no se terminó.
    c.read(entregaControllerProvider.notifier)
      ..seleccionarSolicitante(const Solicitante(
          id: '1', nombre: 'Pedro', dependencia: 'SG', tipo: 'ITSON', zona: 'Taller'))
      ..avanzar();
    expect(c.read(entregaControllerProvider).paso, 1);

    await tester.tap(find.widgetWithText(FilledButton, '+ Nueva entrega'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(VentanillaEntregaPage), findsOneWidget);
    expect(c.read(entregaControllerProvider).paso, 0);
    expect(c.read(entregaControllerProvider).materiales, isEmpty);
  });

  testWidgets('al volver de una entrega terminada el historial se recarga desde la página 1',
      (tester) async {
    final repo = _RepoFalso();
    final (c, router) = await _abrir(tester, repo);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '+ Nueva entrega'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // La entrega termina (el controlador de entrega avisa) y se vuelve a ventanilla.
    repo.total = 21;
    c.read(entregasTerminadasProvider.notifier).avisar();
    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(HistorialEntregasPage), findsOneWidget);
    expect(repo.paginasPedidas, [1, 2, 1]);
    expect(find.text('ENT-2026-0021'), findsOneWidget);
    expect(find.text('Mostrando 9 de 21 registros'), findsOneWidget);
  });

  testWidgets('volver sin terminar una entrega no vuelve a consultar', (tester) async {
    final repo = _RepoFalso();
    final (_, router) = await _abrir(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, '+ Nueva entrega'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    router.pop();
    await tester.pumpAndSettle();

    expect(repo.paginasPedidas, [1]);
  });

  testWidgets('muestra encabezado, importar/exportar Excel, subtítulo y barra inferior del Figma',
      (tester) async {
    await _abrir(tester, _RepoFalso());

    expect(find.text('Registro de entregas de material y/o equipos.'), findsOneWidget);
    expect(find.text('Importar entregas anteriores desde Excel'), findsOneWidget);
    expect(find.text('Exportar Excel'), findsOneWidget);
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    final barra = tester.widget<BarraNavegacionInferior>(find.byType(BarraNavegacionInferior));
    expect(barra.actual, SeccionApp.ventanilla);
    for (final s in SeccionApp.values) {
      expect(find.text(s.etiqueta), findsOneWidget);
    }
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('nueva entrega no muestra el botón de regresar del encabezado', (tester) async {
    await _abrir(tester, _RepoFalso());

    await tester.tap(find.widgetWithText(FilledButton, '+ Nueva entrega'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(VentanillaEntregaPage), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Ventanilla de entregas'), findsOneWidget);
  });

  testWidgets('sin entregas muestra el mensaje de historial vacío', (tester) async {
    await _abrir(tester, _RepoFalso(total: 0));

    expect(find.text('Aún no hay entregas registradas.'), findsOneWidget);
    expect(find.byType(TablaDatos), findsNothing);
    expect(find.widgetWithText(FilledButton, '+ Nueva entrega'), findsOneWidget);
  });

  testWidgets('un error del servidor muestra su mensaje y permite reintentar', (tester) async {
    final repo = _RepoFalso(
        error: const ErrorNegocio('SIN_PERMISO', 'No tienes permiso.'));
    await _abrir(tester, repo);

    expect(find.text('No tienes permiso.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repo.paginasPedidas, [1, 1]);
  });

  test('el controlador pide 9 filas por página, como el Figma', () {
    expect(HistorialEntregasControlador.porPagina, 9);
  });
}
