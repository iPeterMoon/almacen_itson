import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/prestamos/datos/activos_repositorio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

const _paginaVacia = {'datos': [], 'total': 0, 'pagina': 1, 'limite': 20};

({Dio dio, AdaptadorHttpFalso servidor}) _crear({int estado = 200, Object? cuerpo}) {
  final servidor = AdaptadorHttpFalso(estado: estado, cuerpo: cuerpo);
  final dio = crearClienteApi(
    urlBase: 'http://api/api/v1',
    obtenerToken: () async => 'token',
    adaptador: servidor,
  );
  return (dio: dio, servidor: servidor);
}

void main() {
  group('ActivosRepositorio.buscar: parámetros', () {
    test('manda texto, estado y límite cuando se indican los tres', () async {
      final (:dio, :servidor) = _crear(cuerpo: _paginaVacia);

      await ActivosRepositorio(dio).buscar(texto: 'taladro', estado: 'DISPONIBLE', limite: 8);

      expect(servidor.ultimaPeticion!.path, '/activos');
      expect(servidor.ultimaPeticion!.queryParameters, {
        'texto': 'taladro',
        'estado': 'DISPONIBLE',
        'limite': 8,
      });
    });

    test('recorta los espacios del texto', () async {
      final (:dio, :servidor) = _crear(cuerpo: _paginaVacia);

      await ActivosRepositorio(dio).buscar(texto: '  taladro  ');

      expect(servidor.ultimaPeticion!.queryParameters, {'texto': 'taladro'});
    });

    test('no manda el texto si viene vacío o solo con espacios', () async {
      final (:dio, :servidor) = _crear(cuerpo: _paginaVacia);

      await ActivosRepositorio(dio).buscar(texto: '   ', estado: 'DISPONIBLE');

      expect(servidor.ultimaPeticion!.queryParameters, {'estado': 'DISPONIBLE'});
    });

    test('sin ningún filtro no manda parámetros', () async {
      final (:dio, :servidor) = _crear(cuerpo: _paginaVacia);

      await ActivosRepositorio(dio).buscar();

      expect(servidor.ultimaPeticion!.queryParameters, isEmpty);
    });
  });

  group('ActivosRepositorio.buscar: errores de la API como ErrorNegocio', () {
    for (final (codigo, estado, mensaje) in [
      ('ACTIVO_PRESTADO', 409, 'La herramienta ya está en préstamo.'),
      ('ACTIVO_NO_DISPONIBLE', 409, 'La herramienta no está disponible.'),
      ('ACTIVO_NO_ENCONTRADO', 404, 'Activo no encontrado.'),
    ]) {
      test('$codigo ($estado) llega con su código, mensaje y estado HTTP', () async {
        final (:dio, servidor: _) = _crear(
          estado: estado,
          cuerpo: {'codigo': codigo, 'mensaje': mensaje},
        );

        await expectLater(
          ActivosRepositorio(dio).buscar(texto: 'TAL-001'),
          throwsA(
            isA<ErrorNegocio>()
                .having((e) => e.codigo, 'codigo', codigo)
                .having((e) => e.mensaje, 'mensaje', mensaje)
                .having((e) => e.estadoHttp, 'estadoHttp', estado),
          ),
        );
      });
    }
  });
}