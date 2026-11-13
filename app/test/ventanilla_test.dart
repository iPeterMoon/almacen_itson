import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/widgets/componentes.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/validadores.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validarCantidad (Escenario 7)', () {
    test('rechaza vacío, no numérico, cero y negativos', () {
      expect(validarCantidad(''), isNotNull);
      expect(validarCantidad('abc'), isNotNull);
      expect(validarCantidad('0'), 'La cantidad debe ser mayor a cero.');
      expect(validarCantidad('-2'), 'La cantidad debe ser mayor a cero.');
    });

    test('acepta números positivos con punto o coma', () {
      expect(validarCantidad('1'), isNull);
      expect(validarCantidad('0.5'), isNull);
      expect(validarCantidad('2,5'), isNull);
    });
  });

  test('ErrorNegocio.fromJson lee codigo, mensaje y datos', () {
    final e = ErrorNegocio.fromJson({
      'codigo': 'STOCK_INSUFICIENTE',
      'mensaje': 'Existencia insuficiente.',
      'datos': {'disponible': 4},
    });
    expect(e.codigo, 'STOCK_INSUFICIENTE');
    expect(e.datos['disponible'], 4);
  });

  group('Paginación', () {
    test('PaginadorTabla.paginasVisibles agrega puntos suspensivos', () {
      expect(PaginadorTabla.paginasVisibles(1, 3), [1, 2, 3]);
      expect(PaginadorTabla.paginasVisibles(1, 8), [1, 2, null, 8]);
      expect(PaginadorTabla.paginasVisibles(4, 8), [1, null, 3, 4, 5, null, 8]);
      expect(PaginadorTabla.paginasVisibles(8, 8), [1, null, 7, 8]);
    });

    test('el repositorio simulado devuelve páginas con total y número de páginas', () async {
      final repo = VentanillaRepositorioSimulado();
      final p1 = await repo.buscarMateriales(pagina: 1, porPagina: 4);
      final p2 = await repo.buscarMateriales(pagina: 2, porPagina: 4);
      expect(p1.items.length, 4);
      expect(p1.total, p2.total);
      expect(p1.totalPaginas, (p1.total + 3) ~/ 4);
      expect(p2.items.first.codigo, isNot(p1.items.first.codigo));
    });
  });

  group('Selección opcional', () {
    test('se puede deseleccionar al trabajador y a quien autorizó', () {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);

      c.seleccionarSolicitante(const Solicitante(
          id: '1', nombre: 'Pedro', dependencia: 'SG', tipo: 'ITSON', zona: 'Taller'));
      c.setAutorizo('a1');
      expect(contenedor.read(entregaControllerProvider).solicitante, isNotNull);
      expect(contenedor.read(entregaControllerProvider).autorizoId, 'a1');

      c.deseleccionarSolicitante();
      c.setAutorizo(null);
      expect(contenedor.read(entregaControllerProvider).solicitante, isNull);
      expect(contenedor.read(entregaControllerProvider).autorizoId, isNull);
      expect(contenedor.read(entregaControllerProvider).puedeAvanzar(), isFalse);
    });
  });

  group('Agregar material repetido', () {
    test('suma la cantidad en lugar de reemplazarla', () async {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);
      final m = (await VentanillaRepositorioSimulado().buscarMateriales(consulta: 'Guantes')).items.first;

      expect(await c.agregarMaterial(material: m, cantidad: 1, unidad: 'Piezas'), isNull);
      expect(await c.agregarMaterial(material: m, cantidad: 2, unidad: 'Piezas'), isNull);

      final lista = contenedor.read(entregaControllerProvider).materiales;
      expect(lista.length, 1);
      expect(lista.first.cantidad, 3);
    });

    test('rechaza sumar con otra unidad de medida', () async {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);
      final m = (await VentanillaRepositorioSimulado().buscarMateriales(consulta: 'Guantes')).items.first;

      await c.agregarMaterial(material: m, cantidad: 1, unidad: 'Piezas');
      expect(() => c.agregarMaterial(material: m, cantidad: 1, unidad: 'Cajas'),
          throwsA(isA<ErrorNegocio>()));
      expect(contenedor.read(entregaControllerProvider).materiales.first.cantidad, 1);
    });
  });

  group('Revalidación de materiales', () {
    test('las cantidades se redondean a 3 decimales al sumar', () async {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);
      final m = (await VentanillaRepositorioSimulado().buscarMateriales(consulta: 'Guantes')).items.first;

      await c.agregarMaterial(material: m, cantidad: 0.1, unidad: 'Piezas');
      await c.agregarMaterial(material: m, cantidad: 0.2, unidad: 'Piezas');

      expect(contenedor.read(entregaControllerProvider).materiales.first.cantidad, 0.3);
    });

    test('subir la cantidad por encima del límite pide autorización y no la cambia', () async {
      final repo = _RepoConLimite(limite: 2);
      final contenedor = ProviderContainer(
          overrides: [ventanillaRepositorioProvider.overrideWithValue(repo)]);
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);
      final m = (await repo.buscarMateriales(consulta: 'Guantes')).items.first;
      await c.agregarMaterial(material: m, cantidad: 2, unidad: 'Piezas');

      expect(await c.cambiarCantidad(m.codigo, 3), isNotNull);
      expect(contenedor.read(entregaControllerProvider).materiales.first.cantidad, 2);

      c.cambiarCantidadAutorizada(m.codigo, 3, _autorizacion);
      final item = contenedor.read(entregaControllerProvider).materiales.first;
      expect(item.cantidad, 3);
      expect(item.autorizacion, isNotNull);

      // Bajar la cantidad no consulta al servidor.
      final llamadas = repo.validaciones;
      expect(await c.cambiarCantidad(m.codigo, 1), isNull);
      expect(repo.validaciones, llamadas);
    });

    test('al cambiar de solicitante devuelve los materiales que ahora necesitan autorización',
        () async {
      final repo = _RepoConLimite(limite: 5);
      final contenedor = ProviderContainer(
          overrides: [ventanillaRepositorioProvider.overrideWithValue(repo)]);
      addTearDown(contenedor.dispose);
      final c = contenedor.read(entregaControllerProvider.notifier);
      final m = (await repo.buscarMateriales(consulta: 'Guantes')).items.first;
      await c.agregarMaterial(material: m, cantidad: 3, unidad: 'Piezas');

      expect(await c.revalidarMateriales(), isEmpty);
      repo.limite = 2; // otro solicitante con un límite menor
      final pendientes = await c.revalidarMateriales();
      expect(pendientes.single.$1.material.codigo, m.codigo);

      c.autorizarMaterial(m.codigo, _autorizacion);
      expect(await c.revalidarMateriales(), isEmpty);
    });
  });
}

const _autorizacion =
    Autorizacion(autorizadorId: 'a1', autorizadorNombre: 'Leonel Lares', motivo: 'Evento');

// Simulado que pide autorización cuando la cantidad pasa de [limite].
class _RepoConLimite extends VentanillaRepositorioSimulado {
  _RepoConLimite({required this.limite});
  double limite;
  int validaciones = 0;

  @override
  Future<AlertaRestriccion?> validarMaterial({
    Solicitante? solicitante,
    required MaterialCatalogo material,
    required double cantidad,
    required String unidad,
  }) async {
    validaciones++;
    if (cantidad <= limite) return null;
    return const AlertaRestriccion(tipo: TipoAlerta.limiteZona, titulo: 'Límite', regla: 'Máximo');
  }
}
