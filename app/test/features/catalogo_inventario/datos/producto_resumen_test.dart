import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:flutter_test/flutter_test.dart';

// Respuesta real del endpoint con los datos de prueba de Supabase local:
// CD-123 con 12 L en Almacén 1 (E1F1) y 4 L en Almacén 2 (sin ubicación).
const filaPinol = {
  'id': 1,
  'codigo': 'CD-123',
  'nombreEstandar': 'Limpiador multiusos',
  'alias': 'Pinol',
  'categoria': 'Líquido',
  'unidad': 'L',
  'tipo': 'SERVICIOS_GENERALES',
  'masComunes': false,
  'existencia': 16,
  'ultimaEntrada': '2026-11-12T16:57:13.092227+00:00',
  'ultimaSalida': null,
  'ubicaciones': [
    {
      'campusId': 2,
      'almacenId': 5,
      'almacen': 'Almacén 1',
      'ubicacionId': 1,
      'ubicacion': 'E1F1',
      'cantidad': 12,
    },
    {
      'campusId': 2,
      'almacenId': 4,
      'almacen': 'Almacén 2',
      'ubicacionId': 2,
      'ubicacion': null,
      'cantidad': 4,
    },
  ],
};

void main() {
  group('ProductoResumen.fromJson', () {
    test('lee todos los campos de la API', () {
      final producto = ProductoResumen.fromJson(filaPinol);

      expect(producto.id, 1);
      expect(producto.codigo, 'CD-123');
      expect(producto.nombreEstandar, 'Limpiador multiusos');
      expect(producto.alias, 'Pinol');
      expect(producto.categoria, 'Líquido');
      expect(producto.unidad, 'L');
      expect(producto.tipo, 'SERVICIOS_GENERALES');
      expect(producto.masComunes, isFalse);
      expect(producto.existencia, 16.0);
      expect(producto.ultimaEntrada, '2026-11-12T16:57:13.092227+00:00');
      expect(producto.ultimaSalida, isNull);
    });

    test('lee las ubicaciones en el orden del servidor', () {
      final ubicaciones = ProductoResumen.fromJson(filaPinol).ubicaciones;

      expect(ubicaciones, hasLength(2));
      expect(ubicaciones[0].campusId, 2);
      expect(ubicaciones[0].almacenId, 5);
      expect(ubicaciones[0].almacen, 'Almacén 1');
      expect(ubicaciones[0].ubicacionId, 1);
      expect(ubicaciones[0].ubicacion, 'E1F1');
      expect(ubicaciones[0].cantidad, 12.0);
      expect(ubicaciones[1].almacen, 'Almacén 2');
      expect(ubicaciones[1].ubicacion, isNull);
      expect(ubicaciones[1].cantidad, 4.0);
    });

    test('sin "ubicaciones" en la respuesta deja la lista vacía', () {
      final sinUbicaciones = Map<String, dynamic>.of(filaPinol)..remove('ubicaciones');

      expect(ProductoResumen.fromJson(sinUbicaciones).ubicaciones, isEmpty);
    });

    test('acepta un producto sin alias y con existencia decimal', () {
      final producto = ProductoResumen.fromJson({
        ...filaPinol,
        'alias': null,
        'existencia': 7.5,
      });

      expect(producto.alias, isNull);
      expect(producto.existencia, 7.5);
    });

    test('toJson devuelve lo mismo que se leyó', () {
      final json = ProductoResumen.fromJson(filaPinol).toJson();

      expect(json, {
        ...filaPinol,
        'existencia': 16.0,
        'ubicaciones': [
          {...(filaPinol['ubicaciones'] as List)[0] as Map, 'cantidad': 12.0},
          {...(filaPinol['ubicaciones'] as List)[1] as Map, 'cantidad': 4.0},
        ],
      });
    });
  });

  group('ResultadoBusquedaProductos.fromJson', () {
    test('lee la página con sus productos', () {
      final resultado = ResultadoBusquedaProductos.fromJson({
        'datos': [filaPinol],
        'pagina': 1,
        'limite': 8,
      });

      expect(resultado.datos.single.codigo, 'CD-123');
      expect(resultado.datos.single.ubicaciones, hasLength(2));
      expect(resultado.pagina, 1);
      expect(resultado.limite, 8);
      expect(resultado.vacio, isFalse);
    });

    test('una lista vacía significa que no hay coincidencias', () {
      final resultado = ResultadoBusquedaProductos.fromJson({
        'datos': <Object>[],
        'pagina': 1,
        'limite': 8,
      });

      expect(resultado.vacio, isTrue);
    });
  });
}
