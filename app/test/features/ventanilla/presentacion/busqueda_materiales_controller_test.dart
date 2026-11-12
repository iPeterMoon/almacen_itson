import 'dart:async';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/productos_repository.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/busqueda_materiales_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../catalogo_inventario/datos/producto_resumen_test.dart' show filaPinol;

// Repositorio falso: registra cada búsqueda y deja que la prueba decida cuándo y
// con qué responde, para simular respuestas lentas o fuera de orden.
class RepositorioFalso implements ProductosRepository {
  final llamadas = <String>[];
  final _pendientes = <String, Completer<ResultadoBusquedaProductos>>{};

  @override
  Future<ResultadoBusquedaProductos> buscar({
    required String texto,
    int? pagina,
    int? limite,
  }) {
    llamadas.add(texto);
    return (_pendientes[texto] = Completer()).future;
  }

  void responder(String texto, List<ProductoResumen> productos) {
    _pendientes.remove(texto)!.complete(
          ResultadoBusquedaProductos(datos: productos, pagina: 1, limite: 8),
        );
  }

  void fallar(String texto, ErrorNegocio error) => _pendientes.remove(texto)!.completeError(error);
}

final pinol = ProductoResumen.fromJson(filaPinol);
final cloro = ProductoResumen.fromJson({...filaPinol, 'id': 2, 'codigo': 'CD-125', 'nombreEstandar': 'Cloro'});

// Las pruebas usan testWidgets porque su reloj es falso: tester.pump(300 ms)
// avanza el tiempo sin esperar de verdad.
({ProviderContainer contenedor, RepositorioFalso repositorio}) crear() {
  final repositorio = RepositorioFalso();
  final contenedor = ProviderContainer(
    overrides: [proveedorProductosRepository.overrideWithValue(repositorio)],
  );
  // autoDispose: sin un oyente el proveedor se desecharía entre pasos.
  contenedor.listen(proveedorBusquedaMateriales, (_, _) {});
  return (contenedor: contenedor, repositorio: repositorio);
}

void main() {
  testWidgets('empieza inactiva y sin productos', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);

    final estado = contenedor.read(proveedorBusquedaMateriales);

    expect(estado.fase, FaseBusqueda.inactiva);
    expect(estado.productos, isEmpty);
    expect(repositorio.llamadas, isEmpty);
  });

  testWidgets('espera 300 ms sin cambios antes de consultar', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pi');
    await tester.pump(const Duration(milliseconds: 200));
    controlador.cambiarTexto('pin');
    await tester.pump(const Duration(milliseconds: 200));
    controlador.cambiarTexto('pinol');
    await tester.pump(const Duration(milliseconds: 299));

    expect(repositorio.llamadas, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));

    expect(repositorio.llamadas, ['pinol']);
    expect(contenedor.read(proveedorBusquedaMateriales).fase, FaseBusqueda.cargando);
  });

  testWidgets('con resultados queda en conResultados con los productos', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);

    contenedor.read(proveedorBusquedaMateriales.notifier).cambiarTexto('  pinol ');
    await tester.pump(esperaBusqueda);
    repositorio.responder('pinol', [pinol]);
    await tester.pump();

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(repositorio.llamadas, ['pinol']);
    expect(estado.texto, 'pinol');
    expect(estado.fase, FaseBusqueda.conResultados);
    expect(estado.productos.single.codigo, 'CD-123');
  });

  testWidgets('sin coincidencias queda en sinCoincidencias (HU3 E3)', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);

    contenedor.read(proveedorBusquedaMateriales.notifier).cambiarTexto('CD-500');
    await tester.pump(esperaBusqueda);
    repositorio.responder('CD-500', []);
    await tester.pump();

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(estado.fase, FaseBusqueda.sinCoincidencias);
    expect(estado.productos, isEmpty);
  });

  testWidgets('un error queda en la fase error con el mensaje del servidor', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);

    contenedor.read(proveedorBusquedaMateriales.notifier).cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    repositorio.fallar(
      'pinol',
      const ErrorNegocio(ErrorNegocio.codigoSinConexion, ErrorNegocio.mensajeSinConexion),
    );
    await tester.pump();

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(estado.fase, FaseBusqueda.error);
    expect(estado.error!.mensaje, ErrorNegocio.mensajeSinConexion);
  });

  testWidgets('menos de 2 caracteres no consulta y deja la búsqueda inactiva', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('a');
    await tester.pump(esperaBusqueda);
    controlador.cambiarTexto('  b  ');
    await tester.pump(esperaBusqueda);

    expect(repositorio.llamadas, isEmpty);
    expect(contenedor.read(proveedorBusquedaMateriales).fase, FaseBusqueda.inactiva);
  });

  testWidgets('más de 100 caracteres no consulta', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);

    contenedor.read(proveedorBusquedaMateriales.notifier).cambiarTexto('a' * 101);
    await tester.pump(esperaBusqueda);

    expect(repositorio.llamadas, isEmpty);
  });

  testWidgets('borrar el texto limpia los resultados anteriores', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    repositorio.responder('pinol', [pinol]);
    await tester.pump();
    controlador.cambiarTexto('');

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(estado.fase, FaseBusqueda.inactiva);
    expect(estado.productos, isEmpty);
  });

  testWidgets('mientras carga conserva los resultados anteriores', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    repositorio.responder('pinol', [pinol]);
    await tester.pump();
    controlador.cambiarTexto('cloro');
    await tester.pump(esperaBusqueda);

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(estado.fase, FaseBusqueda.cargando);
    expect(estado.productos.single.codigo, 'CD-123');
    repositorio.responder('cloro', [cloro]);
    await tester.pump();
  });

  testWidgets('ignora la respuesta de una búsqueda vieja que llega tarde', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    controlador.cambiarTexto('cloro');
    await tester.pump(esperaBusqueda);

    repositorio.responder('cloro', [cloro]);
    await tester.pump();
    repositorio.responder('pinol', [pinol]);
    await tester.pump();

    final estado = contenedor.read(proveedorBusquedaMateriales);
    expect(repositorio.llamadas, ['pinol', 'cloro']);
    expect(estado.texto, 'cloro');
    expect(estado.productos.single.codigo, 'CD-125');
  });

  testWidgets('ignora una respuesta que llega después de borrar el texto', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    controlador.cambiarTexto('');
    repositorio.responder('pinol', [pinol]);
    await tester.pump();

    expect(contenedor.read(proveedorBusquedaMateriales).fase, FaseBusqueda.inactiva);
  });

  testWidgets('agregar solo espacios al mismo texto no vuelve a consultar', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    repositorio.responder('pinol', [pinol]);
    await tester.pump();
    controlador.cambiarTexto('pinol ');
    await tester.pump(esperaBusqueda);

    expect(repositorio.llamadas, ['pinol']);
  });

  testWidgets('reintentar repite la búsqueda al momento tras un error', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    await tester.pump(esperaBusqueda);
    repositorio.fallar(
      'pinol',
      const ErrorNegocio(ErrorNegocio.codigoSinConexion, ErrorNegocio.mensajeSinConexion),
    );
    await tester.pump();

    final reintento = controlador.reintentar();
    repositorio.responder('pinol', [pinol]);
    await reintento;

    expect(repositorio.llamadas, ['pinol', 'pinol']);
    expect(contenedor.read(proveedorBusquedaMateriales).fase, FaseBusqueda.conResultados);
  });

  testWidgets('limpiar cancela la espera y vuelve al inicio', (tester) async {
    final (:contenedor, :repositorio) = crear();
    addTearDown(contenedor.dispose);
    final controlador = contenedor.read(proveedorBusquedaMateriales.notifier);

    controlador.cambiarTexto('pinol');
    controlador.limpiar();
    await tester.pump(esperaBusqueda);

    expect(repositorio.llamadas, isEmpty);
    expect(contenedor.read(proveedorBusquedaMateriales).texto, '');
  });

  testWidgets('al desechar el proveedor se cancela la espera pendiente', (tester) async {
    final (:contenedor, :repositorio) = crear();

    contenedor.read(proveedorBusquedaMateriales.notifier).cambiarTexto('pinol');
    contenedor.dispose();
    await tester.pump(esperaBusqueda);

    expect(repositorio.llamadas, isEmpty);
  });
}
