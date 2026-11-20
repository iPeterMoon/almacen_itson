import 'package:almacen_itson/core/red/pagina_api.dart';
import 'package:almacen_itson/features/prestamos/datos/activos_repositorio.dart' show Activo;
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart' show ActivoCatalogo;
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/seleccion_activos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/ventanilla_repositorio_api_test.dart'
    show ActivosFalso, rotomartillo, sierraEnReparacion, taladro;
import 'seleccion_activos_test.dart' show abrirActivos, escribir;

// HU8 · Buscador de herramientas en la boleta: el campo de búsqueda va filtrando la
// misma tabla de resultados (código, nombre o serie, con espera de 300 ms y mínimo de
// 2 caracteres). Pruebas: buscar, elegir, no duplicar y el caso sin resultados.

// Servidor de activos falso que sí filtra por código, nombre o serie, como el real.
class ActivosQueFiltran extends ActivosFalso {
  ActivosQueFiltran(this.todos) : super(activos: todos);

  final List<Activo> todos;

  @override
  Future<PaginaApi<Activo>> buscar(
      {String? texto, String? estado, int? pagina, int? limite, bool? soloPrestables}) async {
    llamadas++;
    ultimaConsulta = (texto: texto, estado: estado, pagina: pagina, limite: limite);
    final q = (texto ?? '').toLowerCase();
    final coinciden = todos
        .where((a) =>
            q.isEmpty ||
            a.codigo.toLowerCase().contains(q) ||
            a.nombre.toLowerCase().contains(q) ||
            a.numeroSerie.toLowerCase().contains(q))
        .toList();
    return PaginaApi(
        datos: coinciden, total: coinciden.length, pagina: pagina ?? 1, limite: limite ?? 8);
  }
}

void main() {
  final todos = [taladro, rotomartillo, sierraEnReparacion];

  group('buscar', () {
    testWidgets('espera 300 ms antes de consultar con lo escrito', (tester) async {
      final activos = ActivosQueFiltran(todos);
      await abrirActivos(tester, activos);
      final antes = activos.llamadas;

      await tester.enterText(find.byType(TextField).first, 'tal');
      await tester.pump(const Duration(milliseconds: 299));
      expect(activos.llamadas, antes); // todavía no pasó el debounce

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(seconds: 1));

      expect(activos.ultimaConsulta!.texto, 'tal');
    });

    testWidgets('sin buscar, la tabla lista todos los equipos', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      expect(find.text('Taladro inalámbrico'), findsOneWidget);
      expect(find.text('Rotomartillo SDS Plus'), findsOneWidget);
      expect(find.text('Sierra circular'), findsOneWidget);
    });

    testWidgets('la misma tabla se filtra por código', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      await escribir(tester, '912391');

      expect(find.text('Rotomartillo SDS Plus'), findsOneWidget);
      expect(find.text('Taladro inalámbrico'), findsNothing);
      expect(find.text('Sierra circular'), findsNothing);
      expect(find.text('Resultados'), findsOneWidget);
    });

    testWidgets('la misma tabla se filtra por nombre', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      await escribir(tester, 'sierra');

      expect(find.text('Sierra circular'), findsOneWidget);
      expect(find.text('Taladro inalámbrico'), findsNothing);
    });

    testWidgets('la misma tabla se filtra por número de serie', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      await escribir(tester, 'SN-TAL');

      expect(find.text('Taladro inalámbrico'), findsOneWidget);
      expect(find.text('Rotomartillo SDS Plus'), findsNothing);
    });

    testWidgets('al borrar la búsqueda la tabla vuelve a mostrar todos', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));
      await escribir(tester, 'sierra');

      await escribir(tester, '');

      expect(find.text('Taladro inalámbrico'), findsOneWidget);
      expect(find.text('Sierra circular'), findsOneWidget);
    });

    testWidgets('cada fila trae código, nombre, modelo, serie, ubicación y estado', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      for (final dato in [
        'TAL-001', 'Taladro inalámbrico', 'DCD771', 'SN-TAL-001', 'E1F1', // disponible
        '912391', 'Rotomartillo SDS Plus', 'Bosch GBH 2-28', 'KRC-112233445', 'E1F2', // en préstamo
        '912401', 'Sierra circular', 'Makita 5007MG', 'MK-445566', 'E1F3', // en reparación
      ]) {
        expect(find.text(dato), findsOneWidget, reason: dato);
      }
      expect(find.text('Ubicación'), findsNWidgets(3));
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('En préstamo'), findsOneWidget);
      expect(find.text('En reparación'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con 1 carácter no consulta y pide escribir más', (tester) async {
      final activos = ActivosQueFiltran(todos);
      await abrirActivos(tester, activos);
      final antes = activos.llamadas;

      await escribir(tester, 't');

      expect(activos.llamadas, antes);
      expect(find.text(mensajeActivosEscribeParaBuscar), findsOneWidget);
    });
  });

  group('elegir', () {
    testWidgets('marcar una herramienta filtrada la agrega a la boleta con 1 día', (tester) async {
      final c = await abrirActivos(tester, ActivosQueFiltran(todos));
      await escribir(tester, 'tal');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final agregados = c.read(entregaControllerProvider).activos;
      expect(agregados.single.activo.codigo, 'TAL-001');
      expect(agregados.single.dias, 1);
      expect(find.text('Seleccionados'), findsOneWidget);
      // La tabla sigue filtrada con la búsqueda.
      expect(find.text('Rotomartillo SDS Plus'), findsNothing);
    });

    testWidgets('una herramienta que ya estaba agregada no se duplica', (tester) async {
      final c = await abrirActivos(tester, ActivosQueFiltran(todos));
      await escribir(tester, 'tal');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      final n = c.read(entregaControllerProvider.notifier);
      n.cambiarDias('TAL-001', 3);

      // Se vuelve a agregar la misma herramienta (agregarActivo es el que usa la casilla).
      n.agregarActivo(const ActivoCatalogo(
          codigo: 'TAL-001',
          equipo: 'Taladro inalámbrico',
          modelo: 'DCD771',
          serie: 'SN-TAL-001',
          almacen: 'Principal',
          ubicacion: 'E1F1'));
      await tester.pump();

      final agregados = c.read(entregaControllerProvider).activos;
      expect(agregados, hasLength(1));
      expect(agregados.single.dias, 3); // no se reinició a 1 día
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('en préstamo o en reparación: no tienen casilla y avisan al tocarlas',
        (tester) async {
      final c = await abrirActivos(tester, ActivosQueFiltran(todos));
      await escribir(tester, 'sierra');

      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('Sierra circular'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('912401 no está disponible (En reparación)'), findsOneWidget);
      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });
  });

  group('sin resultados', () {
    testWidgets('muestra que no se encontró ninguna herramienta', (tester) async {
      await abrirActivos(tester, ActivosQueFiltran(todos));

      await escribir(tester, 'zzz-999');

      expect(find.text('No se encontró ninguna herramienta con ese código, nombre o serie'),
          findsOneWidget);
      expect(find.text(mensajeActivoNoEncontrado), findsOneWidget);
      expect(find.text('Taladro inalámbrico'), findsNothing);
    });
  });
}
