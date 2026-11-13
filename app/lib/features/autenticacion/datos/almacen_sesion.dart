import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sesion.dart';

// Contrato para guardar la sesión. En la app se usa el almacenamiento seguro
// del sistema; en las pruebas se reemplaza por una versión en memoria.
abstract interface class AlmacenSesion {
  Future<Sesion?> leer();
  Future<void> guardar(Sesion sesion);
  Future<void> borrar();
}

class AlmacenSesionSeguro implements AlmacenSesion {
  AlmacenSesionSeguro({FlutterSecureStorage? almacenamiento})
      : _almacenamiento = almacenamiento ?? const FlutterSecureStorage();

  static const _clave = 'sesion_almacenes_itson';

  final FlutterSecureStorage _almacenamiento;

  // Caché en memoria: si el almacenamiento del dispositivo falla, la sesión
  // sigue disponible durante esta ejecución (y el login no se cae).
  Sesion? _memoria;
  bool _leido = false;

  @override
  Future<Sesion?> leer() async {
    if (_leido) return _memoria;
    try {
      final texto = await _almacenamiento.read(key: _clave);
      _memoria = texto == null || texto.isEmpty
          ? null
          : Sesion.fromJson((jsonDecode(texto) as Map).cast<String, dynamic>());
    } catch (error) {
      debugPrint('No se pudo leer la sesión guardada: $error');
      _memoria = null;
    }
    _leido = true;
    return _memoria;
  }

  @override
  Future<void> guardar(Sesion sesion) async {
    _memoria = sesion;
    _leido = true;
    try {
      await _almacenamiento.write(key: _clave, value: jsonEncode(sesion.toJson()));
    } catch (error) {
      // La sesión ya quedó en memoria; solo se pierde al cerrar la app.
      debugPrint('No se pudo guardar la sesión: $error');
    }
  }

  @override
  Future<void> borrar() async {
    _memoria = null;
    _leido = true;
    try {
      await _almacenamiento.delete(key: _clave);
    } catch (error) {
      debugPrint('No se pudo borrar la sesión: $error');
    }
  }
}

class AlmacenSesionMemoria implements AlmacenSesion {
  AlmacenSesionMemoria([this._sesion]);

  Sesion? _sesion;

  @override
  Future<Sesion?> leer() async => _sesion;

  @override
  Future<void> guardar(Sesion sesion) async => _sesion = sesion;

  @override
  Future<void> borrar() async => _sesion = null;
}

final proveedorAlmacenSesion = Provider<AlmacenSesion>((ref) => AlmacenSesionSeguro());
