import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_materiales.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/seleccion_activos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/ventanilla_repositorio_api_test.dart'
    show
        ActivosFalso,
        BoletasFalso,
        CatalogosFalso,
        ProductosFalso,
        SupervisoresFalso,
        TrabajadoresFalso,
        rotomartillo,
        sierraEnReparacion,
        taladro;

// HU8 · Pantalla de selección de equipos: pestaña "Activos" del paso 2, con el
// repositorio de la API y un servidor de activos falso, en la tableta del prototipo
// (800 px lógicos de ancho).
Future<ProviderContainer> abrirActivos(WidgetTester tester, ActivosFalso activos) async {
  tester.view.physicalSize = const Size(1200, 1920);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);

  final contenedor = ProviderContainer(
    // Sin reintentos automáticos, como en la app: un error se muestra de inmediato.
    retry: (_, _) => null,
    overrides: [
      ventanillaRepositorioProvider.overrideWithValue(
        VentanillaRepositorioApi(
          ProductosFalso(),
          catalogos: CatalogosFalso(),
          boletas: BoletasFalso(),
          trabajadores: TrabajadoresFalso(),
          supervisores: SupervisoresFalso(),
          activos: activos,
        ),
      ),
    ],
  );
  addTearDown(contenedor.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: contenedor,
    child: const MaterialApp(home: Scaffold(body: PasoMateriales())),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.text('Activos'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return contenedor;
}

// Escribe en el campo de búsqueda y deja pasar la espera de 300 ms y la respuesta.
Future<void> escribir(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField).first, texto);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

String textoDelCampo(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  group('tabla de resultados', () {
    testWidgets('muestra cada activo con su estado; solo los disponibles tienen casilla',
        (tester) async {
      await abrirActivos(tester, ActivosFalso(activos: [taladro, rotomartillo, sierraEnReparacion]));

      expect(find.text('Resultados'), findsOneWidget);
      expect(find.text('TAL-001'), findsOneWidget);
      expect(find.text('DCD771'), findsOneWidget);
      expect(find.text('SN-TAL-001'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('En préstamo'), findsOneWidget);
      expect(find.text('En reparación'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Seleccionados'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pide al servidor todos los estados, no solo los disponibles', (tester) async {
      final activos = ActivosFalso();
      await abrirActivos(tester, activos);

      expect(activos.ultimaConsulta!.estado, isNull);
      expect(activos.ultimaConsulta!.pagina, 1);
      expect(activos.ultimaConsulta!.limite, registrosPorPagina);
    });

    testWidgets('con muchos activos muestra el paginador y pide la página siguiente',
        (tester) async {
      final activos = ActivosFalso(total: 20);
      await abrirActivos(tester, activos);

      expect(find.text('Mostrando 1 de 20 registros'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pump(const Duration(seconds: 1));

      expect(activos.ultimaConsulta!.pagina, 2);
    });
  });

  group('selección', () {
    testWidgets('marcar la casilla agrega el equipo con 1 día y lo muestra en Seleccionados',
        (tester) async {
      final c = await abrirActivos(tester, ActivosFalso());

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final activos = c.read(entregaControllerProvider).activos;
      expect(activos.single.activo.codigo, 'TAL-001');
      expect(activos.single.dias, 1);
      expect(find.text('Seleccionados'), findsOneWidget);
      expect(find.text('Tiempo de préstamo'), findsOneWidget);
      // El código sale en las dos tablas.
      expect(find.text('TAL-001'), findsNWidgets(2));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desmarcar la casilla quita el equipo', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso());

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(c.read(entregaControllerProvider).activos, isEmpty);
      expect(find.text('Seleccionados'), findsNothing);
    });

    testWidgets('tocar la fila también marca el equipo', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso());

      await tester.tap(find.text('Taladro inalámbrico'));
      await tester.pump();

      expect(c.read(entregaControllerProvider).activos, hasLength(1));
    });

    testWidgets('el contador cambia los días de préstamo y no baja de 1', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso());
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final mas = find.byTooltip('Aumentar días de Taladro inalámbrico');
      final menos = find.byTooltip('Disminuir días de Taladro inalámbrico');

      await tester.tap(mas);
      await tester.pump();
      await tester.tap(mas);
      await tester.pump();
      expect(c.read(entregaControllerProvider).activos.single.dias, 3);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(menos);
      await tester.pump();
      await tester.tap(menos);
      await tester.pump();
      expect(c.read(entregaControllerProvider).activos.single.dias, 1);

      // Con 1 día el botón "-" está deshabilitado.
      await tester.tap(menos, warnIfMissed: false);
      await tester.pump();
      expect(c.read(entregaControllerProvider).activos.single.dias, 1);
    });
  });

  group('activos que no se pueden prestar', () {
    testWidgets('en préstamo: avisa y no lo agrega (Escenario 2)', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso(activos: [rotomartillo]));

      await tester.tap(find.text('Rotomartillo SDS Plus'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(mensajeActivoEnPrestamo), findsOneWidget);
      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });

    testWidgets('en reparación: informa que no está disponible (Escenario 3)', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso(activos: [sierraEnReparacion]));

      await tester.tap(find.text('Sierra circular'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(mensajeActivoNoDisponible), findsOneWidget);
      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });

    test('el controlador no agrega activos que no estén disponibles', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(entregaControllerProvider.notifier);

      for (final a in [rotomartillo, sierraEnReparacion]) {
        n.agregarActivo(ActivoCatalogo(
            codigo: a.codigo,
            equipo: a.nombre,
            modelo: a.modelo,
            serie: a.numeroSerie,
            almacen: '',
            ubicacion: '',
            estado: a.estado));
      }

      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });
  });

  group('búsqueda', () {
    testWidgets('el campo permite buscar por código, nombre o serie', (tester) async {
      await abrirActivos(tester, ActivosFalso());

      expect(find.text('Buscar por código, nombre o número de serie del equipo'), findsOneWidget);
    });

    testWidgets('un código que no existe muestra "Activo no encontrado" (Escenario 4)',
        (tester) async {
      final activos = ActivosFalso(activos: const []);
      await abrirActivos(tester, activos);

      await escribir(tester, 'ZZZ-999');

      expect(activos.ultimaConsulta!.texto, 'ZZZ-999');
      expect(find.text(mensajeActivoNoEncontrado), findsOneWidget);
      expect(find.text(mensajeSinHerramientas), findsOneWidget);
    });

    testWidgets('sin activos y sin búsqueda no dice "no encontrado"', (tester) async {
      await abrirActivos(tester, ActivosFalso(activos: const []));

      expect(find.text(mensajeSinActivos), findsOneWidget);
      expect(find.text(mensajeActivoNoEncontrado), findsNothing);
    });

    testWidgets('con 1 carácter pide escribir más y no consulta al servidor', (tester) async {
      final activos = ActivosFalso();
      await abrirActivos(tester, activos);
      final alAbrir = activos.llamadas;

      await escribir(tester, 't');

      expect(find.text(mensajeActivosEscribeParaBuscar), findsOneWidget);
      expect(activos.llamadas, alAbrir);
    });

    testWidgets('cada pestaña conserva su propia búsqueda', (tester) async {
      await abrirActivos(tester, ActivosFalso());

      await escribir(tester, 'taladro');
      expect(textoDelCampo(tester), 'taladro');

      await tester.tap(find.text('Materiales'));
      await tester.pump(const Duration(seconds: 1));
      expect(textoDelCampo(tester), isEmpty);

      await tester.tap(find.text('Activos'));
      await tester.pump(const Duration(seconds: 1));
      expect(textoDelCampo(tester), 'taladro');
    });

    testWidgets('un error del servidor muestra su mensaje', (tester) async {
      await abrirActivos(
        tester,
        ActivosFalso(
          error: const ErrorNegocio('NO_AUTENTICADO', 'Falta el token de sesión.', estadoHttp: 401),
        ),
      );

      expect(find.text('Falta el token de sesión.'), findsOneWidget);
    });

    testWidgets('un error inesperado muestra el mensaje general', (tester) async {
      await abrirActivos(tester, ActivosFalso(error: StateError('fallo')));

      expect(find.text(mensajeErrorActivos), findsOneWidget);
    });
  });

  group('mensajeActivosVacios', () {
    test('según lo que se escribió', () {
      expect(mensajeActivosVacios(''), mensajeSinActivos);
      expect(mensajeActivosVacios(' '), mensajeSinActivos);
      expect(mensajeActivosVacios('a'), mensajeActivosEscribeParaBuscar);
      expect(mensajeActivosVacios('ACT-104'), mensajeActivoNoEncontrado);
    });
  });
}
