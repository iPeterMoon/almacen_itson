import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/avisos_activos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../datos/listas_falsas.dart' show ActivosFalso, rotomartillo, sierraEnReparacion, taladro;
import 'seleccion_activos_test.dart' show abrirActivos;

// HU8 · Avisos al agregar una herramienta: no disponible (E3) y ya prestada (E2)
// bloquean; solicitante con préstamo vencido (E5) solo advierte.

const _juan = Solicitante(
  id: '1',
  nombre: 'Juan Pérez Soto',
  dependencia: 'Servicios Generales',
  tipo: 'ITSON',
  zona: 'Edificio 1800',
  zonaId: 7,
);

Future<void> _tocar(WidgetTester tester, String texto) async {
  await tester.tap(find.text(texto));
  await tester.pumpAndSettle();
}

void main() {
  group('herramienta no disponible (E3)', () {
    testWidgets('bloquea y muestra "<código> no está disponible (<estado>)"', (tester) async {
      final activos = ActivosFalso(activos: [sierraEnReparacion]);
      final c = await abrirActivos(tester, activos);

      await _tocar(tester, 'Sierra circular');

      expect(activos.validaciones.single.codigo, '912401');
      expect(find.text('Activo no disponible'), findsOneWidget);
      expect(find.text('912401 no está disponible (En reparación)'), findsOneWidget);
      expect(find.text('Makita 5007MG'), findsWidgets);
      expect(c.read(entregaControllerProvider).activos, isEmpty);

      await _tocar(tester, 'Cerrar');
      expect(find.text('Activo no disponible'), findsNothing);
    });
  });

  group('herramienta ya prestada (E2)', () {
    testWidgets('bloquea y muestra a quién está prestada y hasta cuándo', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso(activos: [rotomartillo]));

      await _tocar(tester, 'Rotomartillo SDS Plus');

      // Diálogo del prototipo "Detalles de activo en préstamo".
      expect(find.text('Detalles de activo en préstamo'), findsOneWidget);
      expect(find.text('912391 está prestado a Mario Acosta hasta el 19/10/2026'), findsOneWidget);
      expect(find.text('Información General'), findsOneWidget);
      expect(find.text('Mario Acosta'), findsOneWidget);
      expect(find.text('08:57 a.m. 17/10/2026'), findsOneWidget);
      expect(find.text('19/10/2026'), findsOneWidget);
      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });
  });

  group('activo no encontrado (E4)', () {
    testWidgets('muestra "Activo no encontrado" y no lo agrega', (tester) async {
      final c = await abrirActivos(
        tester,
        ActivosFalso(
          activos: [taladro],
          errorAlValidar: const ErrorNegocio('ACTIVO_NO_ENCONTRADO', 'Activo no encontrado.'),
        ),
      );

      await _tocar(tester, 'Taladro inalámbrico');

      expect(find.text('Activo no encontrado'), findsOneWidget);
      expect(c.read(entregaControllerProvider).activos, isEmpty);
    });
  });

  group('solicitante con préstamo vencido (E5)', () {
    testWidgets('muestra el banner amarillo y no bloquea', (tester) async {
      final activos = ActivosFalso(activos: [taladro], conVencido: true);
      final c = await abrirActivos(tester, activos);
      c.read(entregaControllerProvider.notifier).seleccionarSolicitante(_juan);
      await tester.pump();

      await _tocar(tester, 'Taladro inalámbrico');

      expect(activos.validaciones.single.trabajadorId, 1);
      expect(find.text('Juan Pérez Soto tiene un préstamo vencido'), findsOneWidget);
      // Solo advierte: la herramienta se agrega y la boleta puede avanzar.
      final e = c.read(entregaControllerProvider);
      expect(e.activos.single.activo.codigo, 'TAL-001');
      expect(e.copyWith(paso: 1).puedeAvanzar(), isTrue);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('sin vencidos no aparece el banner', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso(activos: [taladro]));
      c.read(entregaControllerProvider.notifier).seleccionarSolicitante(_juan);
      await tester.pump();

      await _tocar(tester, 'Taladro inalámbrico');

      expect(find.textContaining('tiene un préstamo vencido'), findsNothing);
      expect(c.read(entregaControllerProvider).activos, hasLength(1));
    });

    testWidgets('al cambiar de solicitante el aviso desaparece', (tester) async {
      final c = await abrirActivos(tester, ActivosFalso(activos: [taladro], conVencido: true));
      final ctrl = c.read(entregaControllerProvider.notifier)..seleccionarSolicitante(_juan);
      await tester.pump();
      await _tocar(tester, 'Taladro inalámbrico');
      expect(find.text('Juan Pérez Soto tiene un préstamo vencido'), findsOneWidget);

      ctrl.deseleccionarSolicitante();
      await tester.pump();

      expect(find.textContaining('tiene un préstamo vencido'), findsNothing);
    });
  });

  group('errores de activo del servidor', () {
    test('se traducen a los mensajes de la HU8', () {
      expect(mensajeDeError(const ErrorNegocio('ACTIVO_NO_ENCONTRADO', 'Activo no encontrado.')),
          'Activo no encontrado');
      expect(
          mensajeDeError(const ErrorNegocio(
              'ACTIVO_PRESTADO', '912391 está prestado a Mario Acosta hasta el 19/10/2026.')),
          '912391 está prestado a Mario Acosta hasta el 19/10/2026');
      expect(
          mensajeDeError(const ErrorNegocio(
              'ACTIVO_NO_DISPONIBLE', '912401 no está disponible (EN_REPARACION).')),
          '912401 no está disponible (En reparación)');
      expect(
          mensajeDeError(const ErrorNegocio(
              'ACTIVO_NO_DISPONIBLE', 'El activo 912402 ya no está disponible (ROBO_EXTRAVIO).')),
          'El activo 912402 ya no está disponible (ROBO_EXTRAVIO)',
          reason: 'si el texto no tiene la forma esperada se deja el del servidor');
      expect(mensajeDeError(const ErrorNegocio('STOCK_INSUFICIENTE', 'No alcanza.')), 'No alcanza.');
    });

    test('si llegan al crear la boleta, el error se muestra traducido', () async {
      final contenedor = ProviderContainer(overrides: [
        ventanillaRepositorioProvider.overrideWithValue(_RepoQueRechaza(
            const ErrorNegocio('ACTIVO_NO_DISPONIBLE', '912401 no está disponible (DE_BAJA).'))),
      ]);
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier)
        ..seleccionarSolicitante(_juan)
        ..agregarActivo(const ActivoCatalogo(
            codigo: '912401',
            equipo: 'Sierra circular',
            modelo: 'Makita',
            serie: 'MK',
            almacen: '',
            ubicacion: ''))
        ..setFirmaEntrega(Uint8List.fromList([1]))
        ..setFirmaRecibe(Uint8List.fromList([1]));

      await c.confirmar();

      expect(contenedor.read(entregaControllerProvider).error, '912401 no está disponible (De baja)');
    });
  });
}

class _RepoQueRechaza extends VentanillaRepositorioSimulado {
  _RepoQueRechaza(this.error);
  final ErrorNegocio error;

  @override
  Future<ResumenEntrega> registrarEntrega(SolicitudEntrega solicitud) async => throw error;
}
