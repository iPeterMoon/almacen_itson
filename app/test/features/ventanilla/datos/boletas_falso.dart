import 'dart:typed_data';

import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/boletas_repositorio.dart';

// Repositorio de boletas falso: registra lo que se le pide y responde lo indicado.
class BoletasFalso implements BoletasRepositorio {
  BoletasFalso({
    this.validacion = const ValidacionMaterial(
      disponible: 16,
      stockSuficiente: true,
      excedePeriodicidad: false,
      excedeLimite: false,
    ),
    this.creada = const BoletaCreada(boletaId: 7, folio: 'BOL-2026-000007', estado: 'ENTREGADA'),
    this.entregadoEn = '2026-10-17T15:57:00Z',
    this.errorAlCrear,
  });

  ValidacionMaterial validacion;
  BoletaCreada creada;
  String? entregadoEn;
  ErrorNegocio? errorAlCrear;

  final validaciones = <({int productoId, double cantidad, int? trabajadorId, int? zonaId})>[];
  final firmas = <TipoFirma>[];
  Map<String, dynamic>? cuerpoCreado;

  @override
  Future<ValidacionMaterial> validarMaterial({
    required int productoId,
    required double cantidad,
    int? trabajadorId,
    int? zonaId,
  }) async {
    validaciones.add(
        (productoId: productoId, cantidad: cantidad, trabajadorId: trabajadorId, zonaId: zonaId));
    return validacion;
  }

  @override
  Future<String> subirFirma(Uint8List png, TipoFirma tipo) async {
    firmas.add(tipo);
    return tipo == TipoFirma.recibe ? '2/firma-recibe.png' : '2/firma-entrega.png';
  }

  @override
  Future<BoletaCreada> crear(Map<String, dynamic> cuerpo) async {
    cuerpoCreado = cuerpo;
    if (errorAlCrear != null) throw errorAlCrear!;
    return creada;
  }

  @override
  Future<String?> fechaEntrega(int boletaId) async => entregadoEn;
}
