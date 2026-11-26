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
// ordena el servidor. Cada página devuelve su tramo. Como el servidor, filtra por
// solicitante o folio (parcial, sin distinguir mayúsculas) cuando la consulta tiene
// al menos 2 caracteres.
class _RepoFalso extends HistorialEntregasRepositorio {
  _RepoFalso({this.total = 20, this.error}) : super(Dio());

  int total;
  final ErrorNegocio? error;
  final List<int> paginasPedidas = [];
  final List<String> consultas = [];
  final List<DateTime?> desdes = [];
  final List<DateTime?> hastas = [];

  @override
  Future<Pagina<EntregaHistorial>> listar({
    required int pagina,
    required int porPagina,
    String consulta = '',
    DateTime? desde,
    DateTime? hasta,
  }) async {
    paginasPedidas.add(pagina);
    consultas.add(consulta);
    desdes.add(desde);
    hastas.add(hasta);
    if (error != null) throw error!;
    final texto = consulta.trim().toLowerCase();
    final todas = [
      for (var i = 0; i < total; i++)
        EntregaHistorial(
          id: total - i,
          folio: 'ENT-2026-${(total - i).toString().padLeft(4, '0')}',
          solicitante: 'Solicitante ${total - i}',
          dependencia: i == 0 ? null : 'Servicios Generales',
          entregadoEn: '2026-10-20T15:35:00Z',
          supervisor: i == 0 ? null : 'Carlos Mendoza Ruiz',
        ),
    ];
    var filtradas = texto.length < 2
        ? todas
        : todas
            .where((e) =>
                e.folio.toLowerCase().contains(texto) || e.solicitante.toLowerCase().contains(texto))
            .toList();
    if (desde != null || hasta != null) {
      bool enRango(EntregaHistorial e) {
        final f = DateTime.parse(e.entregadoEn!).toUtc();
        final dia = DateTime(f.year, f.month, f.day);
        return (desde == null || !dia.isBefore(desde)) && (hasta == null || !dia.isAfter(hasta));
      }

      filtradas = filtradas.where(enRango).toList();
    }
    final inicio = (pagina - 1) * porPagina;
    return Pagina(
      items: filtradas.skip(inicio).take(porPagina).toList(),
      total: filtradas.length,
      pagina: pagina,
      porPagina: porPagina,
    );
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

  group('buscador', () {
    Finder campo() => find.byType(TextField);

    Future<void> escribir(WidgetTester tester, String texto) async {
      await tester.enterText(campo(), texto);
      await tester.pump(HistorialEntregasPage.esperaBusqueda);
      await tester.pumpAndSettle();
    }

    testWidgets('buscar por nombre del solicitante filtra la tabla y vuelve a la página 1',
        (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await escribir(tester, 'solicitante 1');

      // "Solicitante 1" y de "Solicitante 10" a "Solicitante 19".
      expect(repo.consultas.last, 'solicitante 1');
      expect(repo.paginasPedidas.last, 1);
      expect(find.text('Solicitante 19'), findsOneWidget);
      expect(find.text('Solicitante 20'), findsNothing);
      expect(find.text('Mostrando 9 de 11 registros'), findsOneWidget);
      expect(tester.widget<PaginadorTabla>(find.byType(PaginadorTabla)).pagina, 1);
    });

    testWidgets('buscar por folio muestra solo esa boleta', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);

      await escribir(tester, 'ent-2026-0007');

      expect(repo.consultas.last, 'ent-2026-0007');
      expect(find.text('ENT-2026-0007'), findsOneWidget);
      expect(find.text('ENT-2026-0020'), findsNothing);
      expect(find.text('Mostrando 1 de 1 registros'), findsOneWidget);
    });

    testWidgets('sin coincidencias muestra el mensaje en lugar de la tabla', (tester) async {
      await _abrir(tester, _RepoFalso());

      await escribir(tester, 'Zacarías');

      expect(find.text('No hay boletas que coincidan con la búsqueda'), findsOneWidget);
      expect(find.byType(TablaDatos), findsNothing);
      expect(find.byType(PaginadorTabla), findsNothing);
      expect(find.text('Aún no hay entregas registradas.'), findsNothing);
    });

    testWidgets('espera a que se deje de escribir antes de consultar', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);

      await tester.enterText(campo(), 'EN');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(campo(), 'ENT');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(campo(), 'ENT-2026-0003');
      expect(repo.consultas, [''], reason: 'aún no pasan 300 ms desde la última tecla');

      await tester.pump(HistorialEntregasPage.esperaBusqueda);
      await tester.pumpAndSettle();
      expect(repo.consultas, ['', 'ENT-2026-0003']);
    });

    testWidgets('al borrar el texto regresa al historial completo', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);
      await escribir(tester, 'Zacarías');
      expect(find.text('No hay boletas que coincidan con la búsqueda'), findsOneWidget);

      await escribir(tester, '');

      expect(repo.consultas.last, '');
      expect(find.text('ENT-2026-0020'), findsOneWidget);
      expect(find.text('Mostrando 9 de 20 registros'), findsOneWidget);
    });

    testWidgets('la "x" del campo borra la búsqueda sin esperar', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);
      await escribir(tester, 'ENT-2026-0007');

      await tester.tap(find.byTooltip('Borrar búsqueda'));
      await tester.pumpAndSettle();

      expect(find.text('ENT-2026-0020'), findsOneWidget);
      expect(find.byTooltip('Borrar búsqueda'), findsNothing);
      expect(repo.consultas, ['', 'ENT-2026-0007', '']);
    });

    testWidgets('la paginación conserva la búsqueda', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);
      await escribir(tester, 'solicitante 1');

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(repo.consultas.last, 'solicitante 1');
      expect(find.text('Solicitante 1'), findsOneWidget);
      expect(find.text('Mostrando 2 de 11 registros'), findsOneWidget);
    });

    testWidgets('no deja escribir caracteres que el servidor rechaza', (tester) async {
      await _abrir(tester, _RepoFalso());

      await tester.enterText(campo(), 'Pérez; <ENT> 😀');

      expect(tester.widget<TextField>(campo()).controller!.text, 'Pérez ENT ');
    });
  });

  group('filtro por fecha inline', () {
    testWidgets('el calendario se abre dentro de la tarjeta, sin otra pantalla', (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);

      await tester.tap(find.byTooltip('Filtrar por fecha'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(find.byType(HistorialEntregasPage), findsOneWidget);

      await tester.tap(
          find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('15')));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(repo.desdes.last, DateTime(2026, 11, 15));
      expect(repo.hastas.last, isNull, reason: 'falta elegir el segundo extremo');
    });

    testWidgets('elegir desde y hasta manda el rango inclusivo y vuelve a la página 1',
        (tester) async {
      final repo = _RepoFalso();
      await _abrir(tester, repo);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filtrar por fecha'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('10')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Hasta'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('20')));
      await tester.pumpAndSettle();

      expect(repo.desdes.last, DateTime(2026, 11, 10));
      expect(repo.hastas.last, DateTime(2026, 11, 20));
      expect(repo.paginasPedidas.last, 1);
      expect(find.widgetWithText(OutlinedButton, '10/11/2026'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '20/11/2026'), findsOneWidget);
    });

    testWidgets('quitar el filtro de fecha vuelve al historial completo', (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier).filtrarPorFechas(DateTime(2026, 11, 10),
          hasta: DateTime(2026, 11, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quitar filtro de fecha'));
      await tester.pumpAndSettle();

      expect(repo.desdes.last, isNull);
      expect(repo.hastas.last, isNull);
      expect(repo.paginasPedidas.last, 1);
      expect(find.byTooltip('Quitar filtro de fecha'), findsNothing);
      expect(find.byTooltip('Filtrar por fecha'), findsOneWidget);
    });

    testWidgets('la paginación conserva el rango de fechas', (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier).filtrarPorFechas(DateTime(2026, 10, 1),
          hasta: DateTime(2026, 10, 31));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(repo.desdes.last, DateTime(2026, 10, 1));
      expect(repo.hastas.last, DateTime(2026, 10, 31));
      expect(repo.paginasPedidas, [1, 1, 2]);
    });

    testWidgets('un rango sin entregas muestra el mensaje de fecha, no el de búsqueda',
        (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier).filtrarPorFechas(DateTime(2026, 11, 1),
          hasta: DateTime(2026, 11, 30));
      await tester.pumpAndSettle();

      expect(find.text('No hay entregas en el rango de fechas seleccionado.'), findsOneWidget);
      expect(find.text('No hay boletas que coincidan con la búsqueda'), findsNothing);
    });

    testWidgets('un rango invertido se normaliza antes de consultar', (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier).filtrarPorFechas(DateTime(2026, 10, 31),
          hasta: DateTime(2026, 10, 1));
      await tester.pumpAndSettle();

      expect(repo.desdes.last, DateTime(2026, 10, 1));
      expect(repo.hastas.last, DateTime(2026, 10, 31));
      expect(find.text('Mostrando 9 de 20 registros'), findsOneWidget);
    });

    testWidgets('cambiar de Desde a Hasta reconstruye el calendario con la otra fecha',
        (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier)
          .filtrarPorFechas(DateTime(2026, 10, 10), hasta: DateTime(2026, 11, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filtrar por fecha'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '20/11/2026'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('elegir solo hasta deja el inicio del rango abierto', (tester) async {
      final repo = _RepoFalso();
      final (c, _) = await _abrir(tester, repo);
      await c.read(historialEntregasProvider.notifier)
          .filtrarPorFechas(null, hasta: DateTime(2026, 11, 20));
      await tester.pumpAndSettle();

      expect(repo.desdes.last, isNull);
      expect(repo.hastas.last, DateTime(2026, 11, 20));
      expect(find.widgetWithText(OutlinedButton, 'Desde'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '20/11/2026'), findsOneWidget);
      expect(find.text('Mostrando 9 de 20 registros'), findsOneWidget);
    });
  });

  test('el controlador pide 9 filas por página, como el Figma', () {
    expect(HistorialEntregasControlador.porPagina, 9);
  });
}
