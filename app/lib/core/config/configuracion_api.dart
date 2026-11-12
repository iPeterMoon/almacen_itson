import 'package:flutter_riverpod/flutter_riverpod.dart';

// URL del servidor, leída al compilar. Nunca se escribe en el código:
//   flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1
// (10.0.2.2 es la computadora vista desde el emulador de Android).
const String _urlApiCompilada = String.fromEnvironment('API_URL');

// Devuelve la URL sin la diagonal final, para que las rutas de los repositorios
// ("/catalogo/productos") se unan sin dobles diagonales. Falla con un mensaje
// claro si se olvidó el --dart-define, en vez de llamar a una URL vacía.
String leerUrlApi([String valor = _urlApiCompilada]) {
  final url = valor.trim();
  if (url.isEmpty) {
    throw StateError(
      'Falta API_URL. Ejecuta la app con '
      '--dart-define=API_URL=http://10.0.2.2:3000/api/v1',
    );
  }
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

final proveedorUrlApi = Provider<String>((ref) => leerUrlApi());
