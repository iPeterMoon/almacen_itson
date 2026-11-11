import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:flutter_test/flutter_test.dart';

// Respuesta real del endpoint con los datos de prueba de Supabase local.
const filaPinol = {
  'id': 1,
  'codigo': 'CD-123',
  'nombreEstandar': 'Limpiador multiusos',
  'alias': 'Pinol',
  'categoria': 'Líquido',
  'unidad': 'L',
  'tipo': 'SERVICIOS_GENERALES',
  'masComunes': false,
  'existencia': 12,
  'ultimaEntrada': '2026-11-11T20:17:52.843788+00:00',
  'ultimaSalida': null,
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
      expect(producto.existencia, 12.0);
      expect(producto.ultimaEntrada, '2026-11-11T20:17:52.843788+00:00');
      expect(producto.ultimaSalida, isNull);
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

      expect(json, {...filaPinol, 'existencia': 12.0});
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
