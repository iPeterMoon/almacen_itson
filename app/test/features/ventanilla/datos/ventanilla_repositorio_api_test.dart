import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/productos_repository.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../catalogo_inventario/datos/producto_resumen_test.dart' show filaPinol;

// Repositorio de productos falso: registra cada búsqueda y responde lo indicado.
class ProductosFalso implements ProductosRepository {
  ProductosFalso({this.productos = const [], this.error});

  final List<ProductoResumen> productos;
  final ErrorNegocio? error;
  final llamadas = <({String texto, int? pagina, int? limite})>[];

  @override
  Future<ResultadoBusquedaProductos> buscar({required String texto, int? pagina, int? limite}) async {
    llamadas.add((texto: texto, pagina: pagina, limite: limite));
    if (error != null) throw error!;
    return ResultadoBusquedaProductos(datos: productos, pagina: pagina ?? 1, limite: limite ?? 8);
  }
}

final pinol = ProductoResumen.fromJson(filaPinol);

UbicacionProducto ubicacion(String almacen, String? descripcion) => UbicacionProducto(
      campusId: 2,
      almacenId: 1,
      almacen: almacen,
      ubicacionId: 1,
      ubicacion: descripcion,
      cantidad: 1,
    );

void main() {
  group('buscarMateriales', () {
    test('llama a la API con el texto recortado, la página y el tamaño de página', () async {
      final productos = ProductosFalso(productos: [pinol]);

      final pagina = await VentanillaRepositorioApi(productos)
          .buscarMateriales(consulta: '  pinol ', pagina: 1, porPagina: 8);

      expect(productos.llamadas.single, (texto: 'pinol', pagina: 1, limite: 8));
      expect(pagina.items.single.codigo, 'CD-123');
      expect(pagina.pagina, 1);
      expect(pagina.porPagina, 8);
    });

    test('con menos de 2 caracteres no llama al servidor y devuelve una página vacía', () async {
      final productos = ProductosFalso(productos: [pinol]);
      final repositorio = VentanillaRepositorioApi(productos);

      final vacia = await repositorio.buscarMateriales(consulta: '');
      final unaLetra = await repositorio.buscarMateriales(consulta: '  a  ', soloComunes: true);

      expect(productos.llamadas, isEmpty);
      expect(vacia.items, isEmpty);
      expect(vacia.total, 0);
      expect(unaLetra.items, isEmpty);
    });

    test('ignora los filtros hasta AI-62', () async {
      final productos = ProductosFalso(productos: [pinol]);

      final pagina = await VentanillaRepositorioApi(productos).buscarMateriales(
        consulta: 'pinol',
        categoria: 'Papel',
        tipo: 'Mantenimiento',
        almacen: 'Otro',
        soloComunes: true,
      );

      expect(productos.llamadas.single.texto, 'pinol');
      expect(pagina.items, hasLength(1));
    });

    test('sin coincidencias devuelve una página vacía con total 0', () async {
      final pagina =
          await VentanillaRepositorioApi(ProductosFalso()).buscarMateriales(consulta: 'CD-500');

      expect(pagina.items, isEmpty);
      expect(pagina.total, 0);
      expect(pagina.totalPaginas, 1);
    });

    test('el total cuenta solo lo recibido, sin ofrecer otra página (AI-63)', () async {
      final ocho = List.filled(8, pinol);

      final pagina = await VentanillaRepositorioApi(ProductosFalso(productos: ocho))
          .buscarMateriales(consulta: 'cd', pagina: 1, porPagina: 8);

      expect(pagina.total, 8);
      expect(pagina.totalPaginas, 1);
    });

    test('deja pasar el ErrorNegocio del servidor para que la pantalla lo muestre', () async {
      const error = ErrorNegocio('NO_AUTENTICADO', 'Falta el token de sesión.', estadoHttp: 401);

      await expectLater(
        VentanillaRepositorioApi(ProductosFalso(error: error)).buscarMateriales(consulta: 'pinol'),
        throwsA(same(error)),
      );
    });
  });

  group('aMaterialCatalogo', () {
    test('convierte el producto de la API en el material de la pantalla', () {
      final m = aMaterialCatalogo(pinol);

      expect(m.codigo, 'CD-123');
      expect(m.concepto, 'Limpiador multiusos');
      expect(m.alias, 'Pinol');
      expect(m.categoria, 'Líquido');
      expect(m.tipo, 'Servicios Generales');
      expect(m.esComun, isFalse);
      expect(m.almacen, 'Almacén 1, Almacén 2');
      expect(m.ubicacion, 'Almacén 1: E1F1');
      expect(m.existencia, 16);
      expect(m.unidadBase, 'L');
      expect(m.existenciaTexto, '16 L');
      expect(m.unidades, ['L']);
    });

    test('sin alias deja el texto vacío y traduce cada tipo', () {
      final base = Map<String, dynamic>.of(filaPinol)..['alias'] = null;

      expect(aMaterialCatalogo(ProductoResumen.fromJson(base)).alias, '');
      for (final (api, pantalla) in [
        ('MANTENIMIENTO', 'Mantenimiento'),
        ('AMBOS', 'Ambos'),
        ('OTRO', 'OTRO'),
      ]) {
        final p = ProductoResumen.fromJson({...base, 'tipo': api});
        expect(aMaterialCatalogo(p).tipo, pantalla);
      }
    });
  });

  group('textos de almacén y ubicación', () {
    test('un solo almacén muestra sus ubicaciones sin repetir el almacén', () {
      final lista = [ubicacion('Dormitorios', 'Estante 1'), ubicacion('Dormitorios', 'Estante 2')];

      expect(textoAlmacenes(lista), 'Dormitorios');
      expect(textoUbicaciones(lista), 'Estante 1, Estante 2');
    });

    test('varios almacenes indican a cuál pertenece cada ubicación', () {
      final lista = [ubicacion('Almacén 1', 'E1F1'), ubicacion('Almacén 2', 'Piso 2')];

      expect(textoAlmacenes(lista), 'Almacén 1, Almacén 2');
      expect(textoUbicaciones(lista), 'Almacén 1: E1F1, Almacén 2: Piso 2');
    });

    test('sin ubicaciones o sin descripción se muestra "-"', () {
      expect(textoAlmacenes(const []), '-');
      expect(textoUbicaciones(const []), '-');
      expect(textoUbicaciones([ubicacion('Almacén 2', null), ubicacion('Almacén 2', '  ')]), '-');
    });
  });

  test('los demás métodos siguen en el repositorio simulado', () async {
    final repositorio = VentanillaRepositorioApi(ProductosFalso());

    expect((await repositorio.listarAutorizadores()), isNotEmpty);
    expect((await repositorio.buscarSolicitantes('Rosa')).items.single.nombre, 'Rosa Molina');
    expect(await repositorio.opcionesFiltros(), isA<OpcionesFiltros>());
  });
}
