import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/autenticacion/datos/supervisores_repositorio.dart';
import 'package:almacen_itson/features/prestamos/datos/activos_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/trabajadores_repositorio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

({Dio dio, AdaptadorHttpFalso servidor}) crear({int estado = 200, Object? cuerpo}) {
  final servidor = AdaptadorHttpFalso(estado: estado, cuerpo: cuerpo);
  final dio = crearClienteApi(
    urlBase: 'http://api/api/v1',
    obtenerToken: () async => 'token',
    adaptador: servidor,
  );
  return (dio: dio, servidor: servidor);
}

void main() {
  test('TrabajadoresRepositorio busca con texto y página, y lee las zonas', () async {
    final (:dio, :servidor) = crear(cuerpo: {
      'datos': [
        {
          'id': 1,
          'nombre': 'Juan Pérez Soto',
          'tipo': 'ITSON',
          'compania': null,
          'dependencia': 'SERVICIOS_GENERALES',
          'puesto': 'Intendencia',
          'campusId': 1,
          'zonas': [
            {'id': 7, 'nombre': 'Edificio 1800', 'edificio': '1800', 'piso': null},
          ],
        },
      ],
      'total': 1,
      'pagina': 2,
      'limite': 8,
    });

    final r = await TrabajadoresRepositorio(dio).buscar(texto: ' juan ', pagina: 2, limite: 8);

    expect(servidor.ultimaPeticion!.path, '/trabajadores');
    expect(servidor.ultimaPeticion!.queryParameters, {'texto': 'juan', 'pagina': 2, 'limite': 8});
    expect(r.total, 1);
    expect(r.datos.single.zonas.single.id, 7);
  });

  test('TrabajadoresRepositorio sin texto no manda el parámetro', () async {
    final (:dio, :servidor) =
        crear(cuerpo: {'datos': <Object>[], 'total': 0, 'pagina': 1, 'limite': 8});

    await TrabajadoresRepositorio(dio).buscar(texto: '  ');

    expect(servidor.ultimaPeticion!.queryParameters.containsKey('texto'), isFalse);
  });

  test('SupervisoresRepositorio lee la lista', () async {
    final (:dio, :servidor) = crear(cuerpo: [
      {'id': 'uuid-1', 'nombre': 'Supervisión', 'rol': 'SUPERVISOR', 'campusId': 1},
    ]);

    final lista = await SupervisoresRepositorio(dio).listar();

    expect(servidor.ultimaPeticion!.path, '/usuarios/supervisores');
    expect(lista.single.id, 'uuid-1');
  });

  test('ActivosRepositorio filtra por estado y lee el almacén', () async {
    final (:dio, :servidor) = crear(cuerpo: {
      'datos': [
        {
          'id': 3,
          'codigo': 'TAL-001',
          'nombre': 'Taladro',
          'marca': 'DeWalt',
          'modelo': 'DCD771',
          'numeroSerie': 'SN-1',
          'estado': 'DISPONIBLE',
          'almacen': {'id': 1, 'nombre': 'Principal', 'campusId': 1},
          'ubicacion': null,
        },
      ],
      'total': 1,
      'pagina': 1,
      'limite': 20,
    });

    final r = await ActivosRepositorio(dio).buscar(estado: 'DISPONIBLE', limite: 20);

    expect(servidor.ultimaPeticion!.path, '/activos');
    expect(servidor.ultimaPeticion!.queryParameters, {'estado': 'DISPONIBLE', 'limite': 20});
    expect(r.datos.single.almacen, 'Principal');
    expect(r.datos.single.ubicacion, isNull);
  });

  test('un error del servidor sale como ErrorNegocio', () async {
    final (:dio, servidor: _) = crear(
      estado: 400,
      cuerpo: {'codigo': 'PETICION_INVALIDA', 'mensaje': 'La petición tiene datos inválidos.'},
    );

    await expectLater(
      ActivosRepositorio(dio).buscar(texto: 'a%'),
      throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'PETICION_INVALIDA')),
    );
  });
}
