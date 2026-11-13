import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/ventanilla/datos/boletas_repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../apoyo/adaptador_http_falso.dart';

// Repositorio con un servidor falso que responde [cuerpo] con [estado].
({BoletasRepositorio repo, AdaptadorHttpFalso servidor}) crear({int estado = 200, Object? cuerpo}) {
  final servidor = AdaptadorHttpFalso(estado: estado, cuerpo: cuerpo);
  final dio = crearClienteApi(
    urlBase: 'http://api/api/v1',
    obtenerToken: () async => 'token',
    adaptador: servidor,
  );
  return (repo: BoletasRepositorio(dio), servidor: servidor);
}

void main() {
  test('validarMaterial manda producto y cantidad y lee la respuesta', () async {
    final (:repo, :servidor) = crear(cuerpo: {
      'disponible': 16,
      'ultimaEntrega': null,
      'proximaEntrega': null,
      'diasFaltantes': null,
      'limiteCantidad': null,
      'limiteCadaDias': null,
      'entregadoPeriodo': 0,
      'stockSuficiente': true,
      'cantidadSugerida': null,
      'excedePeriodicidad': false,
      'excedeLimite': false,
    });

    final v = await repo.validarMaterial(productoId: 12, cantidad: 0.5);

    expect(servidor.ultimaPeticion!.method, 'POST');
    expect(servidor.ultimaPeticion!.path, '/boletas/validar-material');
    expect(servidor.ultimaPeticion!.data, {'productoId': 12, 'cantidad': 0.5});
    expect(servidor.ultimaPeticion!.headers['Authorization'], 'Bearer token');
    expect(v.disponible, 16);
    expect(v.stockSuficiente, isTrue);
  });

  test('subirFirma manda la imagen como data URL y devuelve la ruta', () async {
    final (:repo, :servidor) = crear(estado: 201, cuerpo: {'ruta': '2/abc-firma-recibe.png'});

    final ruta = await repo.subirFirma(Uint8List.fromList([1, 2, 3]), TipoFirma.recibe);

    expect(servidor.ultimaPeticion!.path, '/boletas/firmas');
    expect(servidor.ultimaPeticion!.data, {
      'imagenBase64': 'data:image/png;base64,AQID',
      'tipo': 'RECIBE',
    });
    expect(ruta, '2/abc-firma-recibe.png');
  });

  test('crear devuelve folio y estado', () async {
    final (:repo, :servidor) = crear(
      estado: 201,
      cuerpo: {'boletaId': 7, 'folio': 'BOL-2026-000007', 'estado': 'ENTREGADA', 'alertas': []},
    );

    final boleta = await repo.crear({'materiales': []});

    expect(servidor.ultimaPeticion!.path, '/boletas');
    expect(boleta.boletaId, 7);
    expect(boleta.folio, 'BOL-2026-000007');
    expect(boleta.estado, BoletaCreada.entregada);
  });

  test('fechaEntrega lee entregadoEn del detalle', () async {
    final (:repo, :servidor) = crear(cuerpo: {'id': 7, 'entregadoEn': '2026-10-17T15:57:00Z'});

    expect(await repo.fechaEntrega(7), '2026-10-17T15:57:00Z');
    expect(servidor.ultimaPeticion!.path, '/boletas/7');
  });

  test('un error del servidor sale como ErrorNegocio con su código y mensaje', () async {
    final (:repo, servidor: _) = crear(
      estado: 409,
      cuerpo: {'codigo': 'STOCK_INSUFICIENTE', 'mensaje': 'Cloro: solicitado 5, disponible 2.'},
    );

    await expectLater(
      repo.crear({'materiales': []}),
      throwsA(isA<ErrorNegocio>()
          .having((e) => e.codigo, 'codigo', 'STOCK_INSUFICIENTE')
          .having((e) => e.estadoHttp, 'estadoHttp', 409)),
    );
  });

  group('formato de fechas (Hermosillo, UTC-7)', () {
    test('formatearHoraFecha usa 12 horas con a.m./p.m.', () {
      expect(formatearHoraFecha('2026-10-17T15:57:00Z'), '08:57 a.m. 17/10/2026');
      expect(formatearHoraFecha('2026-10-17T20:05:00Z'), '01:05 p.m. 17/10/2026');
    });

    test('formatearFecha cambia de día si en Hermosillo aún es el anterior', () {
      expect(formatearFecha('2026-10-18T03:00:00Z'), '17/10/2026');
    });

    test('un valor nulo o inválido no rompe la pantalla', () {
      expect(formatearFecha(null), '');
      expect(formatearHoraFecha('no-es-fecha'), 'no-es-fecha');
    });
  });
}
