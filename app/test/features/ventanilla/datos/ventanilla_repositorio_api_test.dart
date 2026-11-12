import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos_repository.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/productos_repository.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../catalogo_inventario/datos/producto_resumen_test.dart' show filaPinol;

// Repositorio de productos falso: registra cada búsqueda y responde lo indicado.
class ProductosFalso implements ProductosRepository {
  ProductosFalso({this.productos = const [], this.error});

  final List<ProductoResumen> productos;
  final ErrorNegocio? error;
  final llamadas = <({String? texto, int? pagina, int? limite})>[];
  // Filtros de la última búsqueda (AI-62).
  ({int? categoriaId, String? tipo, int? almacenId, bool soloMasComunes})? ultimosFiltros;

  @override
  Future<ResultadoBusquedaProductos> buscar({
    String? texto,
    int? categoriaId,
    String? tipo,
    int? almacenId,
    bool soloMasComunes = false,
    int? pagina,
    int? limite,
  }) async {
    llamadas.add((texto: texto, pagina: pagina, limite: limite));
    ultimosFiltros = (
      categoriaId: categoriaId,
      tipo: tipo,
      almacenId: almacenId,
      soloMasComunes: soloMasComunes,
    );
    if (error != null) throw error!;
    return ResultadoBusquedaProductos(datos: productos, pagina: pagina ?? 1, limite: limite ?? 8);
  }
}

final pinol = ProductoResumen.fromJson(filaPinol);

// Catálogos falsos: responden lo indicado y cuentan cuántas veces se consultan.
class CatalogosFalso implements CatalogosRepository {
  CatalogosFalso({this.categorias = categoriasPrueba, this.almacenes = almacenesPrueba, this.error});

  final List<Categoria> categorias;
  final List<Almacen> almacenes;
  ErrorNegocio? error;
  var consultas = 0;

  @override
  Future<List<Categoria>> listarCategorias() async {
    consultas++;
    if (error != null) throw error!;
    return categorias;
  }

  @override
  Future<List<Almacen>> listarAlmacenes() async {
    if (error != null) throw error!;
    return almacenes;
  }
}

const categoriasPrueba = [Categoria(id: 3, nombre: 'Bolsas'), Categoria(id: 1, nombre: 'Líquido')];
const almacenesPrueba = [
  Almacen(id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro'),
  Almacen(id: 4, nombre: 'Almacén 2', campusId: 2, campus: 'Centro'),
];

VentanillaRepositorioApi crearApi(ProductosFalso productos, {CatalogosFalso? catalogos}) =>
    VentanillaRepositorioApi(productos, catalogos: catalogos ?? CatalogosFalso());

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

      final pagina = await crearApi(productos)
          .buscarMateriales(consulta: '  pinol ', pagina: 1, porPagina: 8);

      expect(productos.llamadas.single, (texto: 'pinol', pagina: 1, limite: 8));
      expect(pagina.items.single.codigo, 'CD-123');
      expect(pagina.pagina, 1);
      expect(pagina.porPagina, 8);
    });

    test('sin texto lista lo que cumple los filtros (al abrir: "Más comunes")', () async {
      final productos = ProductosFalso(productos: [pinol]);

      final pagina = await crearApi(productos).buscarMateriales(consulta: '  ', soloComunes: true);

      expect(productos.llamadas.single.texto, '');
      expect(productos.ultimosFiltros!.soloMasComunes, isTrue);
      expect(pagina.items.single.codigo, 'CD-123');
    });

    test('con 1 carácter no llama al servidor y devuelve una página vacía', () async {
      final productos = ProductosFalso(productos: [pinol]);

      final unaLetra = await crearApi(productos).buscarMateriales(consulta: '  a  ', soloComunes: true);

      expect(productos.llamadas, isEmpty);
      expect(unaLetra.items, isEmpty);
      expect(unaLetra.total, 0);
    });

    test('convierte los nombres de la pantalla en los ids y códigos de la API', () async {
      final productos = ProductosFalso(productos: [pinol]);

      await crearApi(productos).buscarMateriales(
        consulta: 'pinol',
        categoria: 'Líquido',
        tipo: 'Mantenimiento',
        almacen: 'Almacén 2',
        soloComunes: true,
      );

      expect(productos.llamadas.single.texto, 'pinol');
      expect(productos.ultimosFiltros, (
        categoriaId: 1,
        tipo: 'MANTENIMIENTO',
        almacenId: 4,
        soloMasComunes: true,
      ));
    });

    test('"Todos" sin filtros no manda ninguno ni carga los catálogos', () async {
      final productos = ProductosFalso(productos: [pinol]);
      final catalogos = CatalogosFalso();

      await crearApi(productos, catalogos: catalogos).buscarMateriales();

      expect(productos.ultimosFiltros, (
        categoriaId: null,
        tipo: null,
        almacenId: null,
        soloMasComunes: false,
      ));
      expect(catalogos.consultas, 0);
    });

    test('un nombre que ya no existe en los catálogos no filtra', () async {
      final productos = ProductosFalso(productos: [pinol]);

      await crearApi(productos).buscarMateriales(categoria: 'Ya no existe', almacen: 'Tampoco');

      expect(productos.ultimosFiltros!.categoriaId, isNull);
      expect(productos.ultimosFiltros!.almacenId, isNull);
    });

    test('sin coincidencias devuelve una página vacía con total 0', () async {
      final pagina =
          await crearApi(ProductosFalso()).buscarMateriales(consulta: 'CD-500');

      expect(pagina.items, isEmpty);
      expect(pagina.total, 0);
      expect(pagina.totalPaginas, 1);
    });

    test('el total cuenta solo lo recibido, sin ofrecer otra página (AI-63)', () async {
      final ocho = List.filled(8, pinol);

      final pagina = await crearApi(ProductosFalso(productos: ocho))
          .buscarMateriales(consulta: 'cd', pagina: 1, porPagina: 8);

      expect(pagina.total, 8);
      expect(pagina.totalPaginas, 1);
    });

    test('deja pasar el ErrorNegocio del servidor para que la pantalla lo muestre', () async {
      const error = ErrorNegocio('NO_AUTENTICADO', 'Falta el token de sesión.', estadoHttp: 401);

      await expectLater(
        crearApi(ProductosFalso(error: error)).buscarMateriales(consulta: 'pinol'),
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

  group('opcionesFiltros (AI-62)', () {
    test('trae categorías y almacenes de la API y los tipos fijos', () async {
      final opciones = await crearApi(ProductosFalso()).opcionesFiltros();

      expect(opciones.categorias, ['Bolsas', 'Líquido']);
      expect(opciones.almacenes, ['Almacén 1', 'Almacén 2']);
      expect(opciones.tipos, ['Servicios Generales', 'Mantenimiento']);
    });

    test('distingue por campus los almacenes con el mismo nombre (supervisor jefe)', () async {
      final catalogos = CatalogosFalso(almacenes: const [
        Almacen(id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro'),
        Almacen(id: 7, nombre: 'Principal', campusId: 1, campus: 'Náinari'),
        Almacen(id: 9, nombre: 'Principal', campusId: 3, campus: 'Guaymas'),
      ]);
      final productos = ProductosFalso();
      final api = crearApi(productos, catalogos: catalogos);

      final opciones = await api.opcionesFiltros();
      await api.buscarMateriales(almacen: 'Principal (Guaymas)');

      expect(opciones.almacenes, ['Almacén 1', 'Principal (Náinari)', 'Principal (Guaymas)']);
      expect(productos.ultimosFiltros!.almacenId, 9);
    });

    test('carga los catálogos una sola vez', () async {
      final catalogos = CatalogosFalso();
      final api = crearApi(ProductosFalso(), catalogos: catalogos);

      await api.opcionesFiltros();
      await api.buscarMateriales(categoria: 'Líquido');
      await api.opcionesFiltros();

      expect(catalogos.consultas, 1);
    });

    test('si falla, deja pasar el error y lo reintenta en la siguiente llamada', () async {
      final catalogos = CatalogosFalso(
        error: const ErrorNegocio(ErrorNegocio.codigoSinConexion, ErrorNegocio.mensajeSinConexion),
      );
      final api = crearApi(ProductosFalso(), catalogos: catalogos);

      await expectLater(
        api.opcionesFiltros(),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', ErrorNegocio.codigoSinConexion)),
      );
      catalogos.error = null;

      expect((await api.opcionesFiltros()).categorias, ['Bolsas', 'Líquido']);
      expect(catalogos.consultas, 2);
    });
  });

  test('codigoDeTipo traduce las etiquetas de la pantalla', () {
    expect(codigoDeTipo('Servicios Generales'), 'SERVICIOS_GENERALES');
    expect(codigoDeTipo('Mantenimiento'), 'MANTENIMIENTO');
    expect(codigoDeTipo('Otro'), isNull);
  });

  test('los demás métodos siguen en el repositorio simulado', () async {
    final repositorio = crearApi(ProductosFalso());

    expect((await repositorio.listarAutorizadores()), isNotEmpty);
    expect((await repositorio.buscarSolicitantes('Rosa')).items.single.nombre, 'Rosa Molina');
  });
}
