import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/ventanilla/datos/boletas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
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

  test('con rango de fechas manda desde y hasta en AAAA-MM-DD', () async {
    final (:repo, :servidor) = crear(cuerpo: {'datos': [], 'total': 0});

    await repo.listar(
      pagina: 1,
      porPagina: 9,
      consulta: '  ana  ',
      desde: DateTime(2026, 11, 1),
      hasta: DateTime(2026, 11, 30),
    );

    expect(servidor.ultimaPeticion!.queryParameters, {
      'q': 'ana',
      'desde': '2026-11-01',
      'hasta': '2026-11-30',
      'pagina': 1,
      'porPagina': 9,
    });
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

  test('detalle pide /boletas/:id/detalle y lee datos, materiales, herramientas y autorización',
      () async {
    final (:repo, :servidor) = crear(cuerpo: {
      'id': 184,
      'folio': 'ENT-2026-0184',
      'campusId': 1,
      'campus': 'Náinari',
      'entregadoEn': '2026-10-17T16:35:00Z',
      'entregadoPor': 'Ana Lucía Torres',
      'solicitante': {'nombre': 'Juan Pérez Soto', 'dependencia': 'Mantenimiento', 'unidad': 'Obregón'},
      'autorizoNombre': 'Carlos Mendoza Ruiz',
      'materiales': [
        {
          'codigo': 'CD-987',
          'concepto': 'Pintura epóxica',
          'almacen': 'Mantenimiento',
          'presentacion': 'L',
          'cantidad': 0.5,
        },
        {'codigo': 'CD-1', 'concepto': 'Guantes', 'almacen': null, 'presentacion': null, 'cantidad': 3},
      ],
      'herramientas': [
        {
          'codigo': '912398',
          'nombre': 'Rotomartillo',
          'modelo': 'DCF997D2',
          'numeroSerie': '2023351982',
          'estado': 'EN_PRESTAMO',
        },
      ],
    });

    final d = await repo.detalle(184);

    expect(servidor.ultimaPeticion!.method, 'GET');
    expect(servidor.ultimaPeticion!.path, '/boletas/184/detalle');
    expect(d.folio, 'ENT-2026-0184');
    expect(d.solicitante, 'Juan Pérez Soto');
    expect(d.dependencia, 'Mantenimiento');
    expect(d.unidad, 'Obregón');
    expect(d.campus, 'Náinari');
    expect(d.entregadoPor, 'Ana Lucía Torres');
    expect(d.requirioAutorizacion, isTrue);
    expect(d.materiales.first.cantidadTexto, '0.5 L');
    expect(d.materiales.last.cantidadTexto, '3');
    expect(d.materiales.last.almacen, isNull);
    expect(d.herramientas.single.numeroSerie, '2023351982');
    expect(d.herramientas.single.estado, 'EN_PRESTAMO');
  });

  test('detalle sin autorización ni herramientas', () async {
    final (:repo, servidor: _) = crear(cuerpo: {
      'id': 5,
      'folio': 'ENT-2026-0005',
      'solicitante': {'nombre': 'Externo', 'dependencia': null, 'unidad': null},
      'autorizoNombre': null,
      'materiales': [],
      'herramientas': [],
    });

    final d = await repo.detalle(5);

    expect(d.requirioAutorizacion, isFalse);
    expect(d.herramientas, isEmpty);
  });

  test('detalle de una boleta inexistente sale como ErrorNegocio', () async {
    final (:repo, servidor: _) = crear(
      estado: 404,
      cuerpo: {'codigo': 'BOLETA_NO_EXISTE', 'mensaje': 'La boleta 9 no existe.'},
    );

    expect(
      repo.detalle(9),
      throwsA(isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'BOLETA_NO_EXISTE')),
    );
  });

  test('formatearFechaHora muestra fecha y hora de Hermosillo como el Figma', () {
    expect(formatearFechaHora('2026-10-20T15:35:00Z'), '20/10/2026 08:35 a.m.');
    expect(formatearFechaHora('2026-10-19T20:10:00Z'), '19/10/2026 01:10 p.m.');
  });
}
