import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos_repository.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/producto_resumen.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/productos_repository.dart';
import 'package:almacen_itson/features/ventanilla/datos/boletas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/datos/trabajadores_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/ventanilla_repositorio_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../catalogo_inventario/datos/producto_resumen_test.dart' show filaPinol;
import 'boletas_falso.dart';
import 'listas_falsas.dart';

export 'boletas_falso.dart';
export 'listas_falsas.dart';

// Repositorio de productos falso: registra cada búsqueda y responde lo indicado.
class ProductosFalso implements ProductosRepository {
  ProductosFalso({this.productos = const [], this.error, this.total});

  final List<ProductoResumen> productos;
  final ErrorNegocio? error;
  // Total que responde el servidor falso; si no se indica, los productos recibidos.
  final int? total;
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
    return ResultadoBusquedaProductos(
      datos: productos,
      total: total ?? productos.length,
      pagina: pagina ?? 1,
      limite: limite ?? 8,
    );
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

VentanillaRepositorioApi crearApi(
  ProductosFalso productos, {
  CatalogosFalso? catalogos,
  BoletasFalso? boletas,
  TrabajadoresFalso? trabajadores,
  ActivosFalso? activos,
}) =>
    VentanillaRepositorioApi(
      productos,
      catalogos: catalogos ?? CatalogosFalso(),
      boletas: boletas ?? BoletasFalso(),
      trabajadores: trabajadores ?? TrabajadoresFalso(),
      supervisores: SupervisoresFalso(),
      activos: activos ?? ActivosFalso(),
      entregadoPor: () => 'Alicia García',
    );

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

    test('usa el total del servidor para calcular las páginas (AI-63)', () async {
      final ocho = List.filled(8, pinol);

      final pagina = await crearApi(ProductosFalso(productos: ocho, total: 12))
          .buscarMateriales(pagina: 1, porPagina: 8);

      expect(pagina.items, hasLength(8));
      expect(pagina.total, 12);
      expect(pagina.totalPaginas, 2);
    });

    test('pide la página indicada con el tamaño de página de la tabla (AI-63)', () async {
      final productos = ProductosFalso(productos: [pinol], total: 9);

      final pagina = await crearApi(productos).buscarMateriales(pagina: 2, porPagina: 8);

      expect(productos.llamadas.single, (texto: '', pagina: 2, limite: 8));
      expect(pagina.pagina, 2);
      expect(pagina.items, hasLength(1));
      expect(pagina.total, 9);
    });

    test('una página vacía por cambios de datos trae total 0', () async {
      final pagina = await crearApi(ProductosFalso(total: 0)).buscarMateriales(pagina: 3, porPagina: 8);

      expect(pagina.items, isEmpty);
      expect(pagina.total, 0);
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

  group('buscarSolicitantes', () {
    test('convierte los trabajadores de la API en solicitantes', () async {
      final trabajadores = TrabajadoresFalso(total: 12);

      final pagina = await crearApi(ProductosFalso(), trabajadores: trabajadores)
          .buscarSolicitantes(' juan ', pagina: 2, porPagina: 8);

      expect(trabajadores.ultimaConsulta, (texto: 'juan', pagina: 2, limite: 8));
      expect(pagina.total, 12);
      final s = pagina.items.single;
      expect(s.id, '1');
      expect(s.nombre, 'Juan Pérez Soto');
      expect(s.dependencia, 'Servicios Generales');
      expect(s.tipo, 'ITSON');
      expect(s.zona, 'Edificio 1800 - Planta baja');
      expect(s.zonaId, 7);
    });

    test('con 1 carácter no llama al servidor', () async {
      final trabajadores = TrabajadoresFalso();

      final pagina = await crearApi(ProductosFalso(), trabajadores: trabajadores)
          .buscarSolicitantes('j');

      expect(pagina.items, isEmpty);
      expect(trabajadores.llamadas, 0);
    });

    test('con varias zonas no se elige ninguna y muestra todas', () {
      final s = aSolicitante(const Trabajador(
        id: 2,
        nombre: 'María Sánchez',
        tipo: 'COMPANIA',
        compania: 'Maxi Servicios',
        dependencia: 'MANTENIMIENTO',
        zonas: [ZonaTrabajador(id: 1, nombre: 'A'), ZonaTrabajador(id: 2, nombre: 'B')],
      ));

      expect(s.tipo, 'Maxi Servicios');
      expect(s.zona, 'A, B');
      expect(s.areaTrabajo2, 'B');
      expect(s.zonaId, isNull);
    });
  });

  test('listarAutorizadores devuelve los supervisores con su UUID', () async {
    final lista = await crearApi(ProductosFalso()).listarAutorizadores();

    expect(lista.single.id, supervisorDemo.id);
    expect(lista.single.nombre, 'Supervisión Náinari');
  });

  test('buscarActivos pide solo los disponibles y guarda el id del activo', () async {
    final activos = ActivosFalso();

    final lista = await crearApi(ProductosFalso(), activos: activos).buscarActivos('tal');

    expect(activos.ultimaConsulta, (texto: 'tal', estado: 'DISPONIBLE', limite: 20));
    expect(lista.single.activoId, 3);
    expect(lista.single.equipo, 'Taladro inalámbrico');
    expect(lista.single.serie, 'SN-TAL-001');
  });

  group('validarMaterial', () {
    final material = aMaterialCatalogo(pinol);

    Future<AlertaRestriccion?> validar(BoletasFalso boletas, {double cantidad = 2}) =>
        crearApi(ProductosFalso(), boletas: boletas)
            .validarMaterial(material: material, cantidad: cantidad, unidad: 'L');

    test('manda el id del producto y la cantidad; sin restricción no hay alerta', () async {
      final boletas = BoletasFalso();

      expect(await validar(boletas), isNull);
      expect(boletas.validaciones.single,
          (productoId: 1, cantidad: 2.0, trabajadorId: null, zonaId: null));
    });

    test('con un trabajador registrado manda su id y su zona', () async {
      final boletas = BoletasFalso();

      await crearApi(ProductosFalso(), boletas: boletas).validarMaterial(
        solicitante: aSolicitante(juanPerez),
        material: material,
        cantidad: 2,
        unidad: 'L',
      );

      expect(boletas.validaciones.single,
          (productoId: 1, cantidad: 2.0, trabajadorId: 1, zonaId: 7));
    });

    test('sin existencia suficiente lanza STOCK_INSUFICIENTE con lo disponible', () async {
      final boletas = BoletasFalso(
        validacion: const ValidacionMaterial(
          disponible: 3,
          cantidadSugerida: 3,
          stockSuficiente: false,
          excedePeriodicidad: false,
          excedeLimite: false,
        ),
      );

      await expectLater(
        validar(boletas, cantidad: 5),
        throwsA(isA<ErrorNegocio>()
            .having((e) => e.codigo, 'codigo', 'STOCK_INSUFICIENTE')
            .having((e) => e.mensaje, 'mensaje', contains('hay 3 L'))),
      );
    });

    test('periodicidad no cumplida devuelve la alerta con fechas en Hermosillo', () async {
      final boletas = BoletasFalso(
        validacion: const ValidacionMaterial(
          disponible: 16,
          stockSuficiente: true,
          excedePeriodicidad: true,
          excedeLimite: false,
          ultimaEntrega: '2026-10-17T15:57:00Z',
          proximaEntrega: '2026-10-20T15:57:00Z',
          diasFaltantes: 2,
          limiteCantidad: 0.5,
          limiteCadaDias: 3,
        ),
      );

      final alerta = (await validar(boletas))!;

      expect(alerta.tipo, TipoAlerta.periodicidad);
      expect(alerta.regla, '0.5 L cada 3 días');
      expect(alerta.ultimaEntrega, '08:57 a.m. 17/10/2026');
      expect(alerta.proximaEntrega, '20/10/2026');
      expect(alerta.diasFaltantes, 2);
    });

    test('límite de la zona devuelve lo entregado y lo solicitado', () async {
      final boletas = BoletasFalso(
        validacion: const ValidacionMaterial(
          disponible: 16,
          stockSuficiente: true,
          excedePeriodicidad: false,
          excedeLimite: true,
          limiteCantidad: 3,
          limiteCadaDias: 7,
          entregadoPeriodo: 1,
        ),
      );

      final alerta = (await validar(boletas))!;

      expect(alerta.tipo, TipoAlerta.limiteZona);
      expect(alerta.regla, 'Máximo 3 L cada 7 días');
      expect(alerta.entregado, '1 L');
      expect(alerta.solicitado, '2 L');
    });
  });

  group('registrarEntrega', () {
    final firma = Uint8List.fromList([1, 2, 3]);
    SolicitudEntrega solicitud({
      List<ItemActivo> activos = const [],
      Autorizacion? autorizacion,
    }) =>
        SolicitudEntrega(
          nombreSinRegistro: 'Rosa Molina',
          unidadSinRegistro: 'Navojoa',
          numeroSolicitud: ' OT-9981 ',
          autorizoNombre: 'Leonel Lares',
          materiales: [
            ItemMaterial(
              material: aMaterialCatalogo(pinol),
              cantidad: 2,
              unidad: 'L',
              comentario: 'Baño 2',
              autorizacion: autorizacion,
            ),
          ],
          activos: activos,
          firmaEntrega: firma,
          firmaRecibe: firma,
        );

    test('sube las dos firmas, crea la boleta y arma el resumen', () async {
      final boletas = BoletasFalso();

      final resumen = await crearApi(ProductosFalso(), boletas: boletas).registrarEntrega(solicitud());

      expect(boletas.firmas, containsAll([TipoFirma.recibe, TipoFirma.entrega]));
      expect(boletas.cuerpoCreado, {
        'materiales': [
          {'productoId': 1, 'cantidad': 2.0, 'comentario': 'Baño 2'},
        ],
        'solicitanteNombre': 'Rosa Molina',
        'solicitanteUnidad': 'Navojoa',
        'numeroSolicitud': 'OT-9981',
        'autorizoNombre': 'Leonel Lares',
        'firmaRecibe': '2/firma-recibe.png',
        'firmaEntrega': '2/firma-entrega.png',
      });
      expect(resumen.folio, 'BOL-2026-000007');
      expect(resumen.recibidoPor, 'Rosa Molina');
      expect(resumen.entregadoPor, 'Alicia García');
      expect(resumen.fechaHora, '08:57 a.m. 17/10/2026');
      expect(resumen.materiales.single.detalle, '2 L');
    });

    SolicitudEntrega deJuan({List<ItemActivo> activos = const []}) => SolicitudEntrega(
          solicitanteId: '1',
          solicitante: aSolicitante(juanPerez),
          materiales: solicitud().materiales,
          activos: activos,
          firmaEntrega: firma,
          firmaRecibe: firma,
        );

    test('un trabajador registrado se manda con su id y su zona, sin nombre ni unidad', () async {
      final boletas = BoletasFalso();

      final resumen =
          await crearApi(ProductosFalso(), boletas: boletas).registrarEntrega(deJuan());

      expect(boletas.cuerpoCreado!['trabajadorId'], 1);
      expect(boletas.cuerpoCreado!['zonaId'], 7);
      expect(boletas.cuerpoCreado!.containsKey('solicitanteNombre'), isFalse);
      expect(boletas.cuerpoCreado!.containsKey('solicitanteUnidad'), isFalse);
      expect(resumen.recibidoPor, 'Juan Pérez Soto');
      expect(resumen.area, 'Servicios Generales');
    });

    test('manda el motivo de la excepción y el supervisor elegido', () async {
      final boletas = BoletasFalso();
      const uuid = '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f';

      await crearApi(ProductosFalso(), boletas: boletas).registrarEntrega(solicitud(
        autorizacion: const Autorizacion(
            autorizadorId: uuid, autorizadorNombre: 'Leonel', motivo: 'Otro', detalleOtro: 'Fuga'),
      ));

      expect((boletas.cuerpoCreado!['materiales'] as List).single['motivoExcepcion'], 'Otro: Fuga');
      expect(boletas.cuerpoCreado!['supervisorId'], uuid);
    });

    test('las herramientas se mandan con su id y días, y salen en el resumen', () async {
      final boletas = BoletasFalso();
      final activo = aActivoCatalogo(taladro);

      final resumen = await crearApi(ProductosFalso(), boletas: boletas)
          .registrarEntrega(deJuan(activos: [ItemActivo(activo: activo, dias: 3)]));

      expect(boletas.cuerpoCreado!['herramientas'], [
        {'activoId': 3, 'diasPrestamo': 3},
      ]);
      expect(resumen.activos.single.codigo, 'TAL-001');
      expect(resumen.activos.single.extra, 'SN-TAL-001');
    });

    test('una herramienta sin id del servidor se rechaza antes de subir las firmas', () async {
      final boletas = BoletasFalso();
      const activo = ActivoCatalogo(
          codigo: '912391', equipo: 'Rotomartillo', modelo: 'GBH', serie: 'K1', almacen: '', ubicacion: '');

      await expectLater(
        crearApi(ProductosFalso(), boletas: boletas)
            .registrarEntrega(deJuan(activos: [const ItemActivo(activo: activo)])),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'ACTIVO_NO_ENCONTRADO')),
      );
      expect(boletas.firmas, isEmpty);
    });

    test('una boleta pendiente de autorización regresa su folio marcado como pendiente', () async {
      final boletas = BoletasFalso(
        creada: const BoletaCreada(boletaId: 8, folio: 'BOL-2026-000008', estado: 'PENDIENTE_AUTORIZACION'),
      );

      final resumen =
          await crearApi(ProductosFalso(), boletas: boletas).registrarEntrega(solicitud());

      expect(resumen.folio, 'BOL-2026-000008');
      expect(resumen.autorizacionPendiente, isTrue);
      expect(resumen.fechaHora, 'Pendiente de autorización');
    });

    test('los errores del servidor salen tal cual', () async {
      final boletas = BoletasFalso(
        errorAlCrear: const ErrorNegocio('STOCK_INSUFICIENTE', 'Limpiador: solicitado 2, disponible 1.'),
      );

      await expectLater(
        crearApi(ProductosFalso(), boletas: boletas).registrarEntrega(solicitud()),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'STOCK_INSUFICIENTE')),
      );
    });
  });
}
