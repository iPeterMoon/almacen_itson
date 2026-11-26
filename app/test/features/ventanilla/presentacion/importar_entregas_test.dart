import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/archivos/guardador_archivos.dart';
import 'package:almacen_itson/core/archivos/selector_archivos.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/importacion_entregas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_page.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/importacion_entregas_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/importar_entregas.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _HistorialFalso extends HistorialEntregasRepositorio {
  _HistorialFalso() : super(Dio());

  int total = 0;
  int consultas = 0;

  @override
  Future<Pagina<EntregaHistorial>> listar({
    required int pagina,
    required int porPagina,
    String consulta = '',
    DateTime? desde,
    DateTime? hasta,
  }) async {
    consultas++;
    return Pagina(
      items: [
        for (var i = 1; i <= total; i++)
          EntregaHistorial(id: i, folio: 'BOL-2025-000$i', solicitante: 'Ana López'),
      ],
      total: total,
      pagina: pagina,
      porPagina: porPagina,
    );
  }
}

// Responde lo que la prueba decida con [respuesta].
class _ImportacionFalsa extends ImportacionEntregasRepositorio {
  _ImportacionFalsa() : super(Dio());

  // late: debe crearse dentro de testWidgets (zona de tiempo simulado), no en setUp.
  late final respuesta = Completer<ResultadoImportacion>();
  final List<String> nombres = [];
  void Function(double)? progreso;

  @override
  Future<ResultadoImportacion> importar({
    required String nombre,
    required Uint8List contenido,
    void Function(double fraccion)? alProgresar,
  }) {
    nombres.add(nombre);
    progreso = alProgresar;
    return respuesta.future;
  }
}

class _SelectorFalso extends SelectorArchivos {
  ArchivoElegido? elegido = _archivo();
  Object? fallo;

  @override
  Future<ArchivoElegido?> elegirXlsx() async {
    if (fallo != null) throw fallo!;
    return elegido;
  }
}

class _GuardadorFalso implements GuardadorArchivos {
  Object? fallo;
  (String, Uint8List)? guardado;

  @override
  Future<String> guardarEnDescargas({required String nombre, required Uint8List bytes}) async {
    if (fallo != null) throw fallo!;
    guardado = (nombre, bytes);
    return 'Descargas';
  }
}

ArchivoElegido _archivo({String nombre = 'entregas.xlsx', int? tamano = 4}) =>
    ArchivoElegido(nombre: nombre, tamano: tamano, leer: () async => Uint8List(4));

const _botonImportar = 'Importar entregas anteriores desde Excel';

void main() {
  late _HistorialFalso historial;
  late _ImportacionFalsa importacion;
  late _SelectorFalso archivos;
  late _GuardadorFalso guardador;

  setUp(() {
    historial = _HistorialFalso();
    importacion = _ImportacionFalsa();
    archivos = _SelectorFalso();
    guardador = _GuardadorFalso();
  });

  Future<ProviderContainer> abrir(
    WidgetTester tester, {
    Size logico = const Size(800, 1280),
  }) async {
    tester.view.physicalSize = logico;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      retry: reintentoProveedores,
      overrides: [
        proveedorHistorialEntregasRepositorio.overrideWithValue(historial),
        proveedorImportacionEntregasRepositorio.overrideWithValue(importacion),
        proveedorSelectorArchivos.overrideWithValue(archivos),
        proveedorGuardadorArchivos.overrideWithValue(guardador),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: HistorialEntregasPage()),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> importar(WidgetTester tester) async {
    await tester.tap(find.text(_botonImportar));
    await tester.pump();
    await tester.pump();
  }

  OutlinedButton boton(WidgetTester tester) => tester.widget<OutlinedButton>(
    find.ancestor(
      of: find.text(_botonImportar),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    ),
  );

  testWidgets('importación exitosa: muestra el progreso, el total y recarga el historial', (
    tester,
  ) async {
    await abrir(tester);
    expect(historial.consultas, 1);
    expect(find.text('Aún no hay entregas registradas.'), findsOneWidget);

    await importar(tester);
    expect(importacion.nombres, ['entregas.xlsx']);
    expect(find.text('Enviando archivo… 0 %'), findsOneWidget);
    expect(boton(tester).onPressed, isNull, reason: 'no se puede importar dos veces a la vez');
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.description_outlined)).onPressed,
      isNull,
      reason: 'la plantilla tampoco se descarga mientras se envía',
    );

    importacion.progreso!(0.5);
    await tester.pump();
    expect(find.text('Enviando archivo… 50 %'), findsOneWidget);
    importacion.progreso!(1);
    await tester.pump();
    expect(find.text('Validando e importando las boletas…'), findsOneWidget);

    historial.total = 3;
    importacion.respuesta.complete(const ResultadoImportacion(importadas: 3));
    await tester.pumpAndSettle();

    expect(find.text('Se importaron 3 boletas.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(historial.consultas, 2);
    expect(find.text('BOL-2025-0001'), findsOneWidget);
    expect(boton(tester).onPressed, isNotNull);
  });

  testWidgets('con filtros activos el aviso sugiere quitarlos para ver lo importado', (
    tester,
  ) async {
    final c = await abrir(tester);
    await c.read(historialEntregasProvider.notifier).filtrarPorFechas(DateTime(2026, 11));
    await tester.pumpAndSettle();

    await importar(tester);
    importacion.respuesta.complete(const ResultadoImportacion(importadas: 2));
    await tester.pumpAndSettle();

    expect(find.text('Se importaron 2 boletas. $textoQuitarFiltros'), findsOneWidget);
  });

  testWidgets('con errores: muestra fila y motivo en un diálogo y no recarga el historial', (
    tester,
  ) async {
    await abrir(tester);
    await importar(tester);
    importacion.respuesta.complete(
      const ResultadoImportacion(
        importadas: 0,
        errores: [
          ErrorFilaImportacion(
            fila: 4,
            motivo: 'La cantidad debe ser un número entero mayor a cero.',
          ),
          ErrorFilaImportacion(fila: 7, motivo: 'El folio es obligatorio.'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No se importó ninguna boleta'), findsOneWidget);
    expect(find.text('2 errores'), findsOneWidget);
    for (final texto in [
      'Fila',
      'Motivo',
      '4',
      'La cantidad debe ser un número entero mayor a cero.',
      '7',
      'El folio es obligatorio.',
    ]) {
      expect(find.descendant(of: find.byType(Dialog), matching: find.text(texto)), findsOneWidget);
    }
    expect(find.textContaining('Se import'), findsNothing);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(historial.consultas, 1);
    expect(boton(tester).onPressed, isNotNull);
  });

  testWidgets('muchos errores caben en el diálogo y se pueden recorrer', (tester) async {
    await abrir(tester, logico: const Size(600, 700));
    await importar(tester);
    importacion.respuesta.complete(
      ResultadoImportacion(
        importadas: 0,
        errores: [
          for (var i = 2; i <= 1001; i++)
            ErrorFilaImportacion(fila: i, motivo: 'No existe el material $i en el campus.'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1000 errores'), findsOneWidget);
    await tester.drag(
      find.descendant(of: find.byType(Dialog), matching: find.byType(ListView)),
      const Offset(0, -100000),
    );
    await tester.pumpAndSettle();
    expect(find.text('No existe el material 1001 en el campus.'), findsOneWidget);
  });

  testWidgets('el resultado se muestra aunque se haya desplazado la pantalla', (tester) async {
    historial.total = 9;
    await abrir(tester, logico: const Size(800, 400));
    await importar(tester);
    // Termina la animación del toque, que también mantiene vivo el botón un momento.
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    importacion.respuesta.complete(const ResultadoImportacion(importadas: 1));
    await tester.pumpAndSettle();

    expect(find.text('Se importó 1 boleta.'), findsOneWidget);
  });

  testWidgets('un error del servidor muestra su mensaje y permite reintentar', (tester) async {
    await abrir(tester);
    await importar(tester);
    importacion.respuesta.completeError(
      const ErrorNegocio('SIN_PERMISO', 'No tienes permiso para importar.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para importar.'), findsOneWidget);
    expect(historial.consultas, 1);
    expect(boton(tester).onPressed, isNotNull);
  });

  testWidgets('cancelar el selector no envía nada', (tester) async {
    archivos.elegido = null;
    await abrir(tester);
    await importar(tester);
    await tester.pumpAndSettle();

    expect(importacion.nombres, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(boton(tester).onPressed, isNotNull);
  });

  testWidgets('otro tipo de archivo o más de 5 MB se rechazan sin enviarlos', (tester) async {
    await abrir(tester);
    archivos.elegido = _archivo(nombre: 'entregas.csv');
    await importar(tester);
    await tester.pumpAndSettle();
    expect(find.text(ImportacionEntregasControlador.errorExtension.mensaje), findsOneWidget);

    archivos.elegido = _archivo(tamano: ImportacionEntregasControlador.maximoBytes + 1);
    await importar(tester);
    await tester.pumpAndSettle();
    expect(find.text(ImportacionEntregasControlador.errorTamano.mensaje), findsOneWidget);
    expect(importacion.nombres, isEmpty);
  });

  testWidgets('si el selector falla se avisa', (tester) async {
    archivos.fallo = Exception('sin selector');
    await abrir(tester);
    await importar(tester);
    await tester.pumpAndSettle();
    expect(find.text('No se pudo importar el archivo.'), findsOneWidget);
  });

  testWidgets('descargar plantilla guarda el .xlsx de ejemplo', (tester) async {
    await abrir(tester);
    await tester.tap(find.byTooltip(textoDescargarPlantilla));
    await tester.pumpAndSettle();

    expect(guardador.guardado!.$1, nombrePlantillaImportacion);
    expect(guardador.guardado!.$2, File(rutaPlantillaImportacion).readAsBytesSync());
    expect(find.text('Se guardó $nombrePlantillaImportacion en Descargas.'), findsOneWidget);
  });

  testWidgets('si no se puede guardar la plantilla muestra el motivo', (tester) async {
    guardador.fallo = const ErrorNegocio(
      GuardadorArchivosDispositivo.codigoNoGuardado,
      GuardadorArchivosDispositivo.mensajeNoGuardado,
    );
    await abrir(tester);
    await tester.tap(find.byTooltip(textoDescargarPlantilla));
    await tester.pumpAndSettle();
    expect(find.text(GuardadorArchivosDispositivo.mensajeNoGuardado), findsOneWidget);
  });

  test('la plantilla de la app es igual a la del servidor', () {
    expect(
      File(rutaPlantillaImportacion).readAsBytesSync(),
      File('../servidor/plantillas/$nombrePlantillaImportacion').readAsBytesSync(),
      reason: 'si cambia la del servidor, cópiala a app/assets/plantillas/',
    );
  });
}
