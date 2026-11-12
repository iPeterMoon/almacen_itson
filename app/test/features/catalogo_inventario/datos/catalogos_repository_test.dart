import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos.dart';
import 'package:almacen_itson/features/catalogo_inventario/datos/catalogos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

CatalogosRepository crearRepositorio(AdaptadorHttpFalso adaptador) => CatalogosRepository(
      crearClienteApi(
        urlBase: 'http://servidor/api/v1',
        obtenerToken: () async => 'token-usuario',
        adaptador: adaptador,
      ),
    );

void main() {
  group('Categoria y Almacen', () {
    test('leen y devuelven el JSON del servidor', () {
      const categoria = {'id': 1, 'nombre': 'Líquido'};
      const almacen = {'id': 5, 'nombre': 'Almacén 1', 'campusId': 2, 'campus': 'Centro'};

      expect(Categoria.fromJson(categoria).toJson(), categoria);
      expect(Almacen.fromJson(almacen).toJson(), almacen);
    });

    test('un almacén sin campus deja el nombre vacío', () {
      final almacen = Almacen.fromJson({'id': 5, 'nombre': 'Almacén 1', 'campusId': 2});

      expect(almacen.campus, '');
    });

    test('los tipos del filtro son los dos que acepta la API', () {
      expect(tiposProducto.map((t) => t.codigo), ['SERVICIOS_GENERALES', 'MANTENIMIENTO']);
      expect(tiposProducto.map((t) => t.etiqueta), ['Servicios Generales', 'Mantenimiento']);
    });
  });

  group('CatalogosRepository', () {
    test('listarCategorias llama a GET /catalogo/categorias con el token', () async {
      final adaptador = AdaptadorHttpFalso(cuerpo: [
        {'id': 3, 'nombre': 'Bolsas'},
        {'id': 1, 'nombre': 'Líquido'},
      ]);

      final categorias = await crearRepositorio(adaptador).listarCategorias();

      expect(adaptador.ultimaPeticion!.method, 'GET');
      expect(adaptador.ultimaPeticion!.uri.path, '/api/v1/catalogo/categorias');
      expect(adaptador.ultimaPeticion!.headers['Authorization'], 'Bearer token-usuario');
      expect(categorias.map((c) => c.nombre), ['Bolsas', 'Líquido']);
    });

    test('listarAlmacenes llama a GET /catalogo/almacenes y lee el campus', () async {
      final adaptador = AdaptadorHttpFalso(cuerpo: [
        {'id': 5, 'nombre': 'Almacén 1', 'campusId': 2, 'campus': 'Centro'},
      ]);

      final almacenes = await crearRepositorio(adaptador).listarAlmacenes();

      expect(adaptador.ultimaPeticion!.uri.path, '/api/v1/catalogo/almacenes');
      expect(almacenes.single.id, 5);
      expect(almacenes.single.campus, 'Centro');
    });

    test('una lista vacía devuelve una lista vacía', () async {
      final almacenes = await crearRepositorio(AdaptadorHttpFalso(cuerpo: <Object>[])).listarAlmacenes();

      expect(almacenes, isEmpty);
    });

    test('un 401 sale como ErrorNegocio con el código del servidor', () async {
      final adaptador = AdaptadorHttpFalso(
        estado: 401,
        cuerpo: {'codigo': 'NO_AUTENTICADO', 'mensaje': 'Falta el token de sesión.'},
      );

      await expectLater(
        crearRepositorio(adaptador).listarCategorias(),
        throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'NO_AUTENTICADO')),
      );
    });

    test('sin red sale como ErrorNegocio SIN_CONEXION', () async {
      await expectLater(
        crearRepositorio(AdaptadorHttpFalso(falloDeRed: true)).listarAlmacenes(),
        throwsA(isA<ErrorNegocio>()
            .having((e) => e.codigo, 'codigo', ErrorNegocio.codigoSinConexion)),
      );
    });
  });
}
