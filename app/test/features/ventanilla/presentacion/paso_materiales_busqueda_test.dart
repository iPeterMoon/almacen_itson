import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_materiales.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/ventanilla_repositorio_api_test.dart' show CatalogosFalso, ProductosFalso, pinol;

// Abre el paso 2 de Denise con el repositorio de la API y un servidor falso, en
// la tableta vertical del prototipo (800 px lógicos de ancho).
Future<ProductosFalso> abrirPaso(WidgetTester tester, ProductosFalso productos) async {
  tester.view.physicalSize = const Size(1200, 1920);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);

  final contenedor = ProviderContainer(
    // Sin reintentos automáticos de Riverpod, como en la app (main.dart, parte 6):
    // un error del servidor se muestra de inmediato en lugar de volver a cargar.
    retry: (_, _) => null,
    overrides: [
      ventanillaRepositorioProvider.overrideWithValue(
        VentanillaRepositorioApi(productos, catalogos: CatalogosFalso()),
      ),
    ],
  );
  addTearDown(contenedor.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: contenedor,
    child: const MaterialApp(home: Scaffold(body: PasoMateriales())),
  ));
  await tester.pump(const Duration(seconds: 1));
  return productos;
}

// Escribe en el campo de búsqueda y deja pasar la espera de 300 ms y la respuesta.
Future<void> escribir(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField).first, texto);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('al abrir lista los "Más comunes" sin texto (AI-62)', (tester) async {
    final productos = await abrirPaso(tester, ProductosFalso(productos: [pinol]));

    expect(productos.llamadas.single.texto, '');
    expect(productos.ultimosFiltros!.soloMasComunes, isTrue);
    expect(find.text('CD-123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('los desplegables muestran las categorías y almacenes de la API', (tester) async {
    await abrirPaso(tester, ProductosFalso(productos: [pinol]));

    await tester.tap(find.text('Todos').first);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('con 1 carácter sigue pidiendo escribir más', (tester) async {
    final productos = await abrirPaso(tester, ProductosFalso(productos: [pinol]));

    final alAbrir = productos.llamadas.length;
    await escribir(tester, 'p');

    expect(find.text(mensajeEscribeParaBuscar), findsOneWidget);
    expect(productos.llamadas.length, alAbrir, reason: 'con 1 carácter no se consulta');
  });

  testWidgets('al escribir muestra los materiales con su almacén y existencia', (tester) async {
    final productos = await abrirPaso(tester, ProductosFalso(productos: [pinol]));

    await escribir(tester, 'pinol');

    expect(productos.llamadas.last.texto, 'pinol');
    expect(find.text('CD-123'), findsOneWidget);
    expect(find.text('Limpiador multiusos'), findsOneWidget);
    expect(find.text('Almacén 1, Almacén 2'), findsOneWidget);
    expect(find.text('16 L'), findsOneWidget);
    expect(find.text(mensajeEscribeParaBuscar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin coincidencias muestra "No hay materiales disponibles con ese nombre"',
      (tester) async {
    await abrirPaso(tester, ProductosFalso());

    await escribir(tester, 'CD-500');

    expect(find.text(mensajeSinMateriales), findsOneWidget);
  });

  testWidgets('un error del servidor muestra su mensaje', (tester) async {
    await abrirPaso(
      tester,
      ProductosFalso(
        error: const ErrorNegocio('NO_AUTENTICADO', 'Falta el token de sesión.', estadoHttp: 401),
      ),
    );

    await escribir(tester, 'pinol');

    expect(find.text('Falta el token de sesión.'), findsOneWidget);
  });
}
