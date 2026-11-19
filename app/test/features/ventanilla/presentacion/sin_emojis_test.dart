import 'package:almacen_itson/core/validacion/sin_emojis.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/dialogos/dialogo_agregar_material.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/dialogos/dialogo_autorizacion.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/dialogos/dialogo_comentario.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_solicitante.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/ventanilla_repositorio_api_test.dart' show ProductosFalso, pinol;
import 'paso_materiales_busqueda_test.dart' show abrirPaso;

const _material = MaterialCatalogo(
  codigo: 'JAB-001',
  concepto: 'Jabón líquido',
  alias: 'Jabón de manos',
  categoria: 'Limpieza',
  tipo: 'SERVICIOS_GENERALES',
  almacen: 'Almacén 1',
  ubicacion: 'E1F1',
  existencia: 10,
  unidadBase: 'Litro',
  unidades: ['Litro'],
);

/// Lee el valor real del campo (incluso cuando no tiene TextEditingController propio).
String _texto(WidgetTester tester, Finder campo) => tester
    .widget<EditableText>(find.descendant(of: campo, matching: find.byType(EditableText)))
    .controller
    .text;

Future<void> _escribir(WidgetTester tester, Finder campo, String valor) async {
  await tester.enterText(campo, valor);
  expect(_texto(tester, campo), quitarEmojis(valor),
      reason: 'el emoji no debe quedarse en el campo');
  expect(find.textContaining('😀'), findsNothing);
}

void main() {
  testWidgets('paso 1: ninguno de sus cuatro campos conserva emojis', (tester) async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PasoSolicitante())),
    ));
    await tester.pump(const Duration(seconds: 1));

    // La búsqueda solo está activa con un solicitante registrado.
    await _escribir(
        tester, find.widgetWithText(TextField, 'Buscar por nombre del solicitante'), 'rosa😀');

    contenedor.read(entregaControllerProvider.notifier).usarSinRegistro(true);
    await tester.pump();

    final casos = {
      'Nombre': 'Rosa Valdez😀',
      'Unidad/Campus': 'Mantenimiento😀',
      'No. Solicitud (Opcional)': 'OT-9981😀',
    };
    for (final entry in casos.entries) {
      await _escribir(tester, find.widgetWithText(TextField, entry.key), entry.value);
    }

    final estado = contenedor.read(entregaControllerProvider);
    expect(estado.nombreSinRegistro, 'Rosa Valdez');
    expect(estado.unidadSinRegistro, 'Mantenimiento');
    expect(estado.numeroSolicitud, 'OT-9981');
  });

  testWidgets('paso 2: la búsqueda de materiales no conserva emojis', (tester) async {
    await abrirPaso(tester, ProductosFalso(productos: [pinol]));

    await _escribir(tester, find.byType(TextField).first, 'pinol😀');
  });

  testWidgets('diálogo de cantidad: el emoji se elimina al escribir', (tester) async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: MaterialApp(home: Scaffold(body: DialogoAgregarMaterial(material: _material))),
    ));
    await tester.pumpAndSettle();

    await _escribir(tester, find.byType(TextFormField), '2😀');
  });

  testWidgets('diálogo de comentario: el emoji se elimina al escribir', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => ElevatedButton(
            onPressed: () =>
                mostrarDialogoComentario(context, nombre: 'Jabón', detalle: '1 Litro'),
            child: const Text('Abrir'),
          )),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await _escribir(tester, find.byType(TextField), 'Entregado😀');
  });

  testWidgets('diálogo de autorización: el motivo "Otro" no conserva emojis', (tester) async {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: contenedor,
      child: MaterialApp(
        home: Scaffold(
          body: DialogoAutorizacion(
            material: _material,
            cantidad: 2,
            unidad: 'Litro',
            alerta: const AlertaRestriccion(
              tipo: TipoAlerta.limiteZona,
              titulo: 'Límite',
              regla: 'Máximo 2 Litro',
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));

    await _escribir(tester, find.widgetWithText(TextField, 'Otro'), 'Evento😀');
  });
}
