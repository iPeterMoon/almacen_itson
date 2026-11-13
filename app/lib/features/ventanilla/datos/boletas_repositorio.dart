import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/red/cliente_api.dart';

// Respuesta de POST /boletas/validar-material. Las cantidades vienen en la unidad
// base del producto. Las fechas llegan en ISO 8601 y pueden ser nulas.
class ValidacionMaterial {
  const ValidacionMaterial({
    required this.disponible,
    required this.stockSuficiente,
    required this.excedePeriodicidad,
    required this.excedeLimite,
    this.cantidadSugerida,
    this.ultimaEntrega,
    this.proximaEntrega,
    this.diasFaltantes,
    this.limiteCantidad,
    this.limiteCadaDias,
    this.entregadoPeriodo = 0,
  });

  final double disponible;
  final bool stockSuficiente;
  final bool excedePeriodicidad;
  final bool excedeLimite;
  // Si no alcanza la existencia, la mayor cantidad que sí se puede entregar.
  final double? cantidadSugerida;
  final String? ultimaEntrega;
  final String? proximaEntrega;
  final int? diasFaltantes;
  final double? limiteCantidad;
  final int? limiteCadaDias;
  final double entregadoPeriodo;

  factory ValidacionMaterial.fromJson(Map<String, dynamic> json) => ValidacionMaterial(
        disponible: (json['disponible'] as num).toDouble(),
        stockSuficiente: json['stockSuficiente'] as bool,
        excedePeriodicidad: json['excedePeriodicidad'] as bool? ?? false,
        excedeLimite: json['excedeLimite'] as bool? ?? false,
        cantidadSugerida: (json['cantidadSugerida'] as num?)?.toDouble(),
        ultimaEntrega: json['ultimaEntrega'] as String?,
        proximaEntrega: json['proximaEntrega'] as String?,
        diasFaltantes: (json['diasFaltantes'] as num?)?.toInt(),
        limiteCantidad: (json['limiteCantidad'] as num?)?.toDouble(),
        limiteCadaDias: (json['limiteCadaDias'] as num?)?.toInt(),
        entregadoPeriodo: (json['entregadoPeriodo'] as num?)?.toDouble() ?? 0,
      );
}

// Respuesta de POST /boletas. [estado] es 'ENTREGADA' o 'PENDIENTE_AUTORIZACION':
// lo decide la base, no la app.
class BoletaCreada {
  const BoletaCreada({required this.boletaId, required this.folio, required this.estado});

  static const entregada = 'ENTREGADA';
  static const pendienteAutorizacion = 'PENDIENTE_AUTORIZACION';

  final int boletaId;
  final String folio;
  final String estado;

  factory BoletaCreada.fromJson(Map<String, dynamic> json) => BoletaCreada(
        boletaId: (json['boletaId'] as num).toInt(),
        folio: json['folio'] as String,
        estado: json['estado'] as String,
      );
}

// Quién firma: quien recibe el material o el almacenista que lo entrega.
enum TipoFirma { recibe, entrega }

// Único punto de la app que llama a las rutas /boletas del servidor (HU6).
// Cualquier fallo sale como ErrorNegocio con el mensaje en español del servidor.
class BoletasRepositorio {
  const BoletasRepositorio(this._dio);

  final Dio _dio;

  // No crea nada: solo pregunta si hay existencia y si se rompe la periodicidad o
  // el límite de la zona. Sin [trabajadorId] ni [zonaId] solo se revisa la existencia.
  Future<ValidacionMaterial> validarMaterial({
    required int productoId,
    required double cantidad,
    int? trabajadorId,
    int? zonaId,
  }) {
    return _llamar(() async {
      final respuesta = await _dio.post<Map<String, dynamic>>(
        '/boletas/validar-material',
        data: {
          'productoId': productoId,
          'cantidad': cantidad,
          'trabajadorId': ?trabajadorId,
          'zonaId': ?zonaId,
        },
      );
      return ValidacionMaterial.fromJson(respuesta.data!);
    });
  }

  // Manda la firma en base64 y devuelve la ruta que se pasa al crear la boleta.
  // La app no sube archivos a ningún almacén por su cuenta: lo hace el servidor.
  Future<String> subirFirma(Uint8List png, TipoFirma tipo) {
    return _llamar(() async {
      final respuesta = await _dio.post<Map<String, dynamic>>(
        '/boletas/firmas',
        data: {
          'imagenBase64': 'data:image/png;base64,${base64Encode(png)}',
          'tipo': tipo == TipoFirma.recibe ? 'RECIBE' : 'ENTREGA',
        },
      );
      return respuesta.data!['ruta'] as String;
    });
  }

  // [cuerpo] sigue CrearBoletaDto del servidor (camelCase).
  Future<BoletaCreada> crear(Map<String, dynamic> cuerpo) {
    return _llamar(() async {
      final respuesta = await _dio.post<Map<String, dynamic>>('/boletas', data: cuerpo);
      return BoletaCreada.fromJson(respuesta.data!);
    });
  }

  // Fecha y hora de entrega (ISO 8601) de una boleta; null si aún no se entrega.
  Future<String?> fechaEntrega(int boletaId) {
    return _llamar(() async {
      final respuesta = await _dio.get<Map<String, dynamic>>('/boletas/$boletaId');
      return respuesta.data!['entregadoEn'] as String?;
    });
  }

  Future<T> _llamar<T>(Future<T> Function() peticion) async {
    try {
      return await peticion();
    } on DioException catch (error) {
      throw ErrorNegocio.desdeDio(error);
    }
  }
}

final proveedorBoletasRepositorio = Provider<BoletasRepositorio>(
  (ref) => BoletasRepositorio(ref.watch(proveedorClienteApi)),
);

// Los almacenes están en Hermosillo (UTC-7 todo el año, sin horario de verano),
// así que la hora se muestra en esa zona aunque el dispositivo tenga otra.
DateTime? _aHermosillo(String? iso) {
  final fecha = iso == null ? null : DateTime.tryParse(iso);
  return fecha?.toUtc().subtract(const Duration(hours: 7));
}

String _dos(int n) => n.toString().padLeft(2, '0');

// "20/10/2026". Si la fecha no es válida devuelve el texto tal cual.
String formatearFecha(String? iso) {
  final f = _aHermosillo(iso);
  if (f == null) return iso ?? '';
  return '${_dos(f.day)}/${_dos(f.month)}/${f.year}';
}

// "08:57 a.m. 17/10/2026", como lo muestra el Figma.
String formatearHoraFecha(String? iso) {
  final f = _aHermosillo(iso);
  if (f == null) return iso ?? '';
  final hora12 = f.hour % 12 == 0 ? 12 : f.hour % 12;
  final sufijo = f.hour < 12 ? 'a.m.' : 'p.m.';
  return '${_dos(hora12)}:${_dos(f.minute)} $sufijo ${formatearFecha(iso)}';
}
