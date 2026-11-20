import 'package:almacen_itson/features/ventanilla/datos/dias_prestamo.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _taladro = ActivoCatalogo(
    codigo: 'TAL-001',
    equipo: 'Taladro inalámbrico',
    modelo: 'DCD771',
    serie: 'SN-TAL-001',
    almacen: 'Principal',
    ubicacion: 'E1F1');

// HU8 · Días de préstamo en el controlador: valor por defecto, límites y bloqueo del paso.
void main() {
  late ProviderContainer contenedor;
  late EntregaController c;
  EntregaState estado() => contenedor.read(entregaControllerProvider);
  int dias() => estado().activos.single.dias;

  setUp(() {
    contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    c = contenedor.read(entregaControllerProvider.notifier);
    c.seleccionarSolicitante(const Solicitante(
        id: '1', nombre: 'Pedro', dependencia: 'SG', tipo: 'ITSON', zona: 'Taller'));
    c.avanzar(); // paso 2: materiales y equipo
    c.agregarActivo(_taladro);
  });

  test('una herramienta se agrega con el valor por defecto', () {
    expect(dias(), diasPrestamoPredeterminado);
  });

  group('cambiarDias', () {
    test('acepta valores entre 1 y 365', () {
      c.cambiarDias('TAL-001', 30);
      expect(dias(), 30);
      c.cambiarDias('TAL-001', 365);
      expect(dias(), 365);
    });

    test('no pasa de 365', () {
      c.cambiarDias('TAL-001', 366);
      expect(dias(), 365);
    });

    test('0 se acepta (campo vacío) para poder bloquear el paso; un negativo queda en 0', () {
      c.cambiarDias('TAL-001', 0);
      expect(dias(), 0);
      c.cambiarDias('TAL-001', -4);
      expect(dias(), 0);
    });

    test('solo cambia la herramienta indicada', () {
      c.agregarActivo(const ActivoCatalogo(
          codigo: 'ACT-2',
          equipo: 'Sierra',
          modelo: 'M',
          serie: 'S',
          almacen: 'Principal',
          ubicacion: 'U'));

      c.cambiarDias('ACT-2', 9);

      expect(estado().activos.map((a) => a.dias), [1, 9]);
    });
  });

  group('escribirDias', () {
    test('lo escrito pasa a días', () {
      c.escribirDias('TAL-001', '12');
      expect(dias(), 12);
    });

    test('vacío o 0 dejan 0 días', () {
      c.escribirDias('TAL-001', '');
      expect(dias(), 0);
      c.escribirDias('TAL-001', '0');
      expect(dias(), 0);
    });

    test('más de 365 se queda en 365', () {
      c.escribirDias('TAL-001', '900');
      expect(dias(), 365);
    });
  });

  group('no se puede continuar con días vacíos o en 0', () {
    test('con días válidos se puede avanzar', () {
      expect(estado().hayDiasInvalidos, isFalse);
      expect(estado().puedeAvanzar(), isTrue);
    });

    test('con 0 días no se puede avanzar', () {
      c.cambiarDias('TAL-001', 0);

      expect(estado().hayDiasInvalidos, isTrue);
      expect(estado().puedeAvanzar(), isFalse);
      c.avanzar();
      expect(estado().paso, 1); // se queda en el paso de materiales
    });

    test('con el campo vacío no se puede avanzar', () {
      c.escribirDias('TAL-001', '');

      expect(estado().puedeAvanzar(), isFalse);
    });

    test('basta una herramienta con 0 días entre varias válidas', () {
      c.agregarActivo(const ActivoCatalogo(
          codigo: 'ACT-2',
          equipo: 'Sierra',
          modelo: 'M',
          serie: 'S',
          almacen: 'Principal',
          ubicacion: 'U'));
      c.cambiarDias('ACT-2', 0);

      expect(estado().puedeAvanzar(), isFalse);
    });

    test('al corregir los días se puede avanzar', () {
      c.cambiarDias('TAL-001', 0);
      c.cambiarDias('TAL-001', 2);

      expect(estado().puedeAvanzar(), isTrue);
      c.avanzar();
      expect(estado().paso, 2);
    });

    test('quitar la herramienta inválida también desbloquea', () {
      c.cambiarDias('TAL-001', 0);
      c.quitarActivo('TAL-001');
      c.agregarActivo(const ActivoCatalogo(
          codigo: 'ACT-2',
          equipo: 'Sierra',
          modelo: 'M',
          serie: 'S',
          almacen: 'Principal',
          ubicacion: 'U'));

      expect(estado().puedeAvanzar(), isTrue);
    });
  });
}
