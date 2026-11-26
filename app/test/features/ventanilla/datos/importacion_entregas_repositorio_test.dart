import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/ventanilla/datos/importacion_entregas_repositorio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

({ImportacionEntregasRepositorio repo, AdaptadorHttpFalso servidor}) crear({
  int estado = 200,
  Object? cuerpo,
  bool falloDeRed = false,
}) {
  final servidor = AdaptadorHttpFalso(estado: estado, cuerpo: cuerpo, falloDeRed: falloDeRed);
  final dio = crearClienteApi(
    urlBase: 'http://api/api/v1',
    obtenerToken: () async => 'token',
    adaptador: servidor,
  );
  return (repo: ImportacionEntregasRepositorio(dio), servidor: servidor);
}

final _contenido = Uint8List.fromList([0x50, 0x4b, 3, 4]);

void main() {
  test('importar manda el .xlsx como multipart en el campo "archivo"', () async {
    final (:repo, :servidor) = crear(cuerpo: {'importadas': 3, 'errores': []});

    final resultado = await repo.importar(nombre: 'entregas.xlsx', contenido: _contenido);

    expect(resultado.exitosa, isTrue);
    expect(resultado.importadas, 3);
    final peticion = servidor.ultimaPeticion!;
    expect(peticion.method, 'POST');
    expect(peticion.path, '/boletas/importar');
    expect(peticion.headers['Authorization'], 'Bearer token');
    expect(peticion.contentType, startsWith(Headers.multipartFormDataContentType));
    final archivo = (peticion.data as FormData).files.single;
    expect(archivo.key, 'archivo');
    expect(archivo.value.filename, 'entregas.xlsx');
    expect(archivo.value.length, _contenido.length);
  });

  test('el 422 con filas inválidas es un resultado con errores, no una excepción', () async {
    final (:repo, servidor: _) = crear(estado: 422, cuerpo: {
      'importadas': 0,
      'errores': [
        {'fila': 4, 'motivo': 'La cantidad debe ser un número entero mayor a cero.'},
        {'fila': 7, 'motivo': 'El folio es obligatorio.'},
      ],
    });

    final resultado = await repo.importar(nombre: 'entregas.xlsx', contenido: _contenido);

    expect(resultado.exitosa, isFalse);
    expect(resultado.importadas, 0);
    expect([for (final e in resultado.errores) (e.fila, e.motivo)], [
      (4, 'La cantidad debe ser un número entero mayor a cero.'),
      (7, 'El folio es obligatorio.'),
    ]);
  });

  test('otros errores (archivo corrupto, 422 de negocio) salen como ErrorNegocio', () async {
    for (final estado in [400, 422]) {
      final (:repo, servidor: _) = crear(
        estado: estado,
        cuerpo: {'codigo': 'ARCHIVO_INVALIDO', 'mensaje': 'No se pudo leer el archivo XLSX.'},
      );
      await expectLater(
        repo.importar(nombre: 'entregas.xlsx', contenido: _contenido),
        throwsA(isA<ErrorNegocio>()
            .having((e) => e.mensaje, 'mensaje', 'No se pudo leer el archivo XLSX.')),
      );
    }
  });

  test('un 422 sin filas con error no se toma como importación exitosa', () async {
    final (:repo, servidor: _) = crear(estado: 422, cuerpo: {'importadas': 0, 'errores': []});

    await expectLater(
      repo.importar(nombre: 'entregas.xlsx', contenido: _contenido),
      throwsA(isA<ErrorNegocio>()),
    );
  });

  test('si el servidor tarda en responder pide revisar el historial antes de reintentar', () async {
    final (:repo, :servidor) = crear();
    servidor.tiempoAgotado = true;

    await expectLater(
      repo.importar(nombre: 'entregas.xlsx', contenido: _contenido),
      throwsA(isA<ErrorNegocio>()
          .having((e) => e.codigo, 'codigo', 'TIEMPO_AGOTADO')
          .having((e) => e.mensaje, 'mensaje', contains('Revisa el historial'))),
    );
  });

  test('sin red avisa que no hay conexión', () async {
    final (:repo, servidor: _) = crear(falloDeRed: true);

    await expectLater(
      repo.importar(nombre: 'entregas.xlsx', contenido: _contenido),
      throwsA(isA<ErrorNegocio>()
          .having((e) => e.codigo, 'codigo', ErrorNegocio.codigoSinConexion)),
    );
  });
}
