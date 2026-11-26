import 'dart:convert';
import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/ventanilla/datos/boletas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

({HistorialEntregasRepositorio repo, AdaptadorHttpFalso servidor}) crear({
  int estado = 200,
  Object? cuerpo,
}) {
  final servidor = AdaptadorHttpFalso(estado: estado, cuerpo: cuerpo);
  final dio = crearClienteApi(
    urlBase: 'http://api/api/v1',
    obtenerToken: () async => 'token',
    adaptador: servidor,
  );
  return (repo: HistorialEntregasRepositorio(dio), servidor: servidor);
}

void main() {
  test('listar pide la página y lee { datos, total } del historial', () async {
    final (:repo, :servidor) = crear(cuerpo: {
      'datos': [
        {
          'id': 191,
          'folio': 'ENT-2026-0191',
          'solicitanteNombre': 'Marisol Duarte Cota',
          'dependencia': 'Servicios Generales',
          'entregadoEn': '2026-10-20T15:35:00Z',
          'autorizoNombre': 'Carlos Mendoza Ruiz',
        },
        {
          'id': 190,
          'folio': 'ENT-2026-0190',
          'solicitanteNombre': 'Roberto Salas Vega',
          'dependencia': null,
          'entregadoEn': null,
          'autorizoNombre': null,
        },
      ],
      'total': 130,
    });

    final pagina = await repo.listar(pagina: 2, porPagina: 9);

    expect(servidor.ultimaPeticion!.method, 'GET');
    expect(servidor.ultimaPeticion!.path, '/boletas/historial');
    expect(servidor.ultimaPeticion!.queryParameters, {'pagina': 2, 'porPagina': 9});
    expect(servidor.ultimaPeticion!.headers['Authorization'], 'Bearer token');
    expect(pagina.total, 130);
    expect(pagina.pagina, 2);
    expect(pagina.totalPaginas, 15);
    expect(pagina.items.first.folio, 'ENT-2026-0191');
    expect(pagina.items.first.supervisor, 'Carlos Mendoza Ruiz');
    expect(pagina.items.last.dependencia, isNull);
    expect(pagina.items.last.supervisor, isNull);
  });

  test('con búsqueda manda q sin espacios a los lados', () async {
    final (:repo, :servidor) = crear(cuerpo: {'datos': [], 'total': 0});

    await repo.listar(pagina: 1, porPagina: 9, consulta: '  ENT-2026-0191 ');

    expect(servidor.ultimaPeticion!.queryParameters,
        {'q': 'ENT-2026-0191', 'pagina': 1, 'porPagina': 9});
  });

  test('con menos de 2 caracteres no manda q y pide el historial completo', () async {
    final (:repo, :servidor) = crear(cuerpo: {'datos': [], 'total': 0});

    await repo.listar(pagina: 1, porPagina: 9, consulta: ' m ');

    expect(servidor.ultimaPeticion!.queryParameters, {'pagina': 1, 'porPagina': 9});
  });

  test('sin entregas responde una página vacía', () async {
    final (:repo, servidor: _) = crear(cuerpo: {'datos': [], 'total': 0});

    final pagina = await repo.listar(pagina: 1, porPagina: 9);

    expect(pagina.items, isEmpty);
    expect(pagina.total, 0);
  });

  test('un error del servidor sale como ErrorNegocio con su mensaje', () async {
    final (:repo, servidor: _) = crear(
      estado: 403,
      cuerpo: {'codigo': 'SIN_PERMISO', 'mensaje': 'No tienes permiso para ver el historial.'},
    );

    expect(
      repo.listar(pagina: 1, porPagina: 9),
      throwsA(isA<ErrorNegocio>()
          .having((e) => e.mensaje, 'mensaje', 'No tienes permiso para ver el historial.')),
    );
  });

  test('formatearFechaHora muestra fecha y hora de Hermosillo como el Figma', () {
    expect(formatearFechaHora('2026-10-20T15:35:00Z'), '20/10/2026 08:35 a.m.');
    expect(formatearFechaHora('2026-10-19T20:10:00Z'), '19/10/2026 01:10 p.m.');
  });

  group('exportar (AI-79)', () {
    // Bytes de prueba con forma de .xlsx (un .xlsx es un ZIP y empieza con "PK").
    final excel = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);

    ({HistorialEntregasRepositorio repo, _ServidorArchivoFalso servidor}) crearExportar({
      int estado = 200,
      List<int>? bytes,
      Map<String, List<String>> encabezados = const {},
    }) {
      final servidor = _ServidorArchivoFalso(estado: estado, bytes: bytes ?? excel, encabezados: encabezados);
      final dio = crearClienteApi(
        urlBase: 'http://api/api/v1',
        obtenerToken: () async => 'token',
        adaptador: servidor,
      );
      return (repo: HistorialEntregasRepositorio(dio), servidor: servidor);
    }

    test('pide el Excel con la búsqueda y lee el archivo, su nombre y el total', () async {
      final (:repo, :servidor) = crearExportar(encabezados: {
        'content-disposition': ['attachment; filename="historial-entregas-2026-11-25.xlsx"'],
        'x-total-resultados': ['13'],
      });

      final archivo = await repo.exportar(consulta: '  jose avila ');

      expect(servidor.ultimaPeticion!.method, 'GET');
      expect(servidor.ultimaPeticion!.path, '/boletas/historial/exportar');
      expect(servidor.ultimaPeticion!.queryParameters, {'q': 'jose avila'});
      expect(servidor.ultimaPeticion!.responseType, ResponseType.bytes);
      expect(servidor.ultimaPeticion!.headers['Authorization'], 'Bearer token');
      expect(archivo.nombre, 'historial-entregas-2026-11-25.xlsx');
      expect(archivo.bytes, excel);
      expect(archivo.total, 13);
      expect(archivo.recortado, isFalse);
    });

    test('sin búsqueda o con 1 carácter no manda q y exporta todo el historial', () async {
      final (:repo, :servidor) = crearExportar();

      await repo.exportar();
      expect(servidor.ultimaPeticion!.queryParameters, isEmpty);

      await repo.exportar(consulta: 'j');
      expect(servidor.ultimaPeticion!.queryParameters, isEmpty);
    });

    test('marca el archivo como recortado si hay más boletas que el tope de filas', () async {
      final (:repo, servidor: _) = crearExportar(encabezados: {
        'x-total-resultados': ['1500'],
      });

      final archivo = await repo.exportar();

      expect(archivo.total, 1500);
      expect(archivo.recortado, isTrue);
    });

    test('sin encabezados usa un nombre genérico y total 0', () async {
      final (:repo, servidor: _) = crearExportar();

      final archivo = await repo.exportar();

      expect(archivo.nombre, 'historial-entregas.xlsx');
      expect(archivo.total, 0);
    });

    test('un error del servidor sale como ErrorNegocio con su mensaje', () async {
      final (:repo, servidor: _) = crearExportar(
        estado: 400,
        bytes: utf8.encode(jsonEncode({'codigo': 'PETICION_INVALIDA', 'mensaje': 'La petición tiene datos inválidos.'})),
        encabezados: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

      await expectLater(
        repo.exportar(consulta: 'jose'),
        throwsA(isA<ErrorNegocio>()
            .having((e) => e.codigo, 'codigo', 'PETICION_INVALIDA')
            .having((e) => e.mensaje, 'mensaje', 'La petición tiene datos inválidos.')
            .having((e) => e.estadoHttp, 'estadoHttp', 400)),
      );
    });
  });

  test('nombreDeArchivo lee el nombre de Content-Disposition', () {
    expect(nombreDeArchivo('attachment; filename="historial-entregas-2026-11-25.xlsx"'),
        'historial-entregas-2026-11-25.xlsx');
    expect(nombreDeArchivo('attachment; filename=historial.xlsx'), 'historial.xlsx');
    expect(nombreDeArchivo(null), 'historial-entregas.xlsx');
    expect(nombreDeArchivo('attachment'), 'historial-entregas.xlsx');
  });
}

// Servidor falso que responde bytes (un archivo) con los encabezados indicados.
class _ServidorArchivoFalso implements HttpClientAdapter {
  _ServidorArchivoFalso({required this.estado, required this.bytes, required this.encabezados});

  final int estado;
  final List<int> bytes;
  final Map<String, List<String>> encabezados;
  RequestOptions? ultimaPeticion;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ultimaPeticion = options;
    return ResponseBody.fromBytes(bytes, estado, headers: encabezados);
  }

  @override
  void close({bool force = false}) {}
}
