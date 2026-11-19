import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Las búsquedas no deben sobrevivir al cambio de paso: al volver, la barra aparece vacía
// y la tabla tampoco puede seguir filtrada.
void main() {
  late ProviderContainer contenedor;
  late EntregaController c;

  setUp(() {
    contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    c = contenedor.read(entregaControllerProvider.notifier);
    c.seleccionarSolicitante(const Solicitante(
        id: '1', nombre: 'Pedro', dependencia: 'SG', tipo: 'ITSON', zona: 'Taller'));
  });

  test('al retroceder del paso de materiales se limpian las búsquedas de equipo y material', () {
    c.avanzar();
    expect(contenedor.read(entregaControllerProvider).paso, 1);
    contenedor.read(consultaActivosProvider.notifier).set('tal');
    contenedor.read(filtroMaterialesProvider.notifier)
      ..setConsulta('pinol')
      ..setCategoria('Líquido');

    c.retroceder();

    expect(contenedor.read(entregaControllerProvider).paso, 0);
    expect(contenedor.read(consultaActivosProvider), '');
    expect(contenedor.read(filtroMaterialesProvider).consulta, '');
    // Los filtros de categoría, tipo y almacén se ven en pantalla: se conservan.
    expect(contenedor.read(filtroMaterialesProvider).categoria, 'Líquido');
  });

  test('al avanzar desde el paso del solicitante se limpia su búsqueda', () {
    contenedor.read(consultaSolicitantesProvider.notifier).set('mar');

    c.avanzar();

    expect(contenedor.read(consultaSolicitantesProvider), '');
  });

  test('al volver al paso del solicitante su tabla no queda filtrada', () {
    c.avanzar();
    contenedor.read(consultaSolicitantesProvider.notifier).set('mar');

    c.retroceder();

    expect(contenedor.read(consultaSolicitantesProvider), '');
  });

  test('al empezar una boleta nueva no queda ninguna búsqueda anterior', () {
    contenedor.read(consultaSolicitantesProvider.notifier).set('mar');
    contenedor.read(consultaActivosProvider.notifier).set('tal');
    contenedor.read(filtroMaterialesProvider.notifier).setConsulta('pinol');

    c.reiniciar();

    expect(contenedor.read(consultaSolicitantesProvider), '');
    expect(contenedor.read(consultaActivosProvider), '');
    expect(contenedor.read(filtroMaterialesProvider).consulta, '');
  });

  test('la página de la tabla de equipos vuelve a la 1', () {
    c.avanzar();
    contenedor.read(consultaActivosProvider.notifier).set('tal');
    contenedor.read(paginaActivosProvider.notifier).set(3);

    c.retroceder();

    expect(contenedor.read(paginaActivosProvider), 1);
  });
}
