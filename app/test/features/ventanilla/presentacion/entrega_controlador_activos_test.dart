import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _taladro = ActivoCatalogo(
  codigo: 'TAL-001',
  equipo: 'Taladro',
  modelo: 'GBH 2-28',
  serie: 'SN-1',
  almacen: 'Mantenimiento',
  ubicacion: 'Estante 1',
  activoId: 3,
);

const _sierra = ActivoCatalogo(
  codigo: 'SIE-002',
  equipo: 'Sierra circular',
  modelo: 'GKS 190',
  serie: 'SN-2',
  almacen: 'Mantenimiento',
  ubicacion: 'Estante 2',
  activoId: 4,
);

const _pinol = MaterialCatalogo(
  codigo: 'CD-123',
  concepto: 'Limpiador multiusos',
  alias: 'Pinol',
  categoria: 'Líquido',
  tipo: 'Servicios Generales',
  almacen: 'Dormitorios',
  ubicacion: 'Estante 2',
  existencia: 12,
  unidadBase: 'L',
  unidades: ['Litros'],
);

void main() {
  late ProviderContainer contenedor;

  setUp(() {
    contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
  });

  EntregaController controlador() => contenedor.read(entregaControllerProvider.notifier);
  EntregaState estado() => contenedor.read(entregaControllerProvider);

  group('herramientas en la boleta (HU8)', () {
    test('agrega una herramienta con 1 día de préstamo por defecto', () {
      controlador().agregarActivo(_taladro);

      expect(estado().activos, hasLength(1));
      expect(estado().activos.single.activo.codigo, 'TAL-001');
      expect(estado().activos.single.dias, 1);
    });

    test('no duplica una herramienta que ya está en la boleta', () {
      controlador()
        ..agregarActivo(_taladro)
        ..agregarActivo(_taladro);

      expect(estado().activos, hasLength(1));
    });

    test('cambia los días de préstamo solo de la herramienta indicada', () {
      controlador()
        ..agregarActivo(_taladro)
        ..agregarActivo(_sierra)
        ..cambiarDias('TAL-001', 5);

      expect(estado().activos.firstWhere((a) => a.activo.codigo == 'TAL-001').dias, 5);
      expect(estado().activos.firstWhere((a) => a.activo.codigo == 'SIE-002').dias, 1);
    });

    test('los días de préstamo no bajan de 1', () {
      controlador()
        ..agregarActivo(_taladro)
        ..cambiarDias('TAL-001', 3)
        ..cambiarDias('TAL-001', 0)
        ..cambiarDias('TAL-001', -2);

      expect(estado().activos.single.dias, 3);
    });

    test('quita solo la herramienta indicada', () {
      controlador()
        ..agregarActivo(_taladro)
        ..agregarActivo(_sierra)
        ..quitarActivo('TAL-001');

      expect(estado().activos.map((a) => a.activo.codigo), ['SIE-002']);
    });

    test('quitar un código que no está en la boleta no cambia nada', () {
      controlador()
        ..agregarActivo(_taladro)
        ..quitarActivo('NO-EXISTE');

      expect(estado().activos, hasLength(1));
    });

    test('totalPartidas cuenta materiales y herramientas', () {
      controlador()
        ..agregarMaterialConMotivo(
          material: _pinol,
          cantidad: 1,
          unidad: 'Litros',
          motivoExcepcion: const MotivoExcepcion(motivo: 'Evento'),
        )
        ..agregarActivo(_taladro)
        ..agregarActivo(_sierra);

      expect(estado().totalPartidas, 3);

      controlador().quitarActivo('SIE-002');
      expect(estado().totalPartidas, 2);

      controlador().quitarMaterial('CD-123');
      expect(estado().totalPartidas, 1);
    });
  });
}