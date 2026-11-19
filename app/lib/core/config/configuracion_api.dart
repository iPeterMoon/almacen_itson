import 'package:flutter_riverpod/flutter_riverpod.dart';

// URL del servidor, leída al compilar. Nunca se escribe en el código:
//   flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1
// (10.0.2.2 es la computadora vista desde el emulador de Android).
const String _urlApiCompilada = String.fromEnvironment('API_URL');

const String _prefijoApi = '/api/v1';

// Devuelve la URL base sin la diagonal final y con el prefijo de la API, para
// que las rutas de los repositorios ("/usuarios/sesion") caigan siempre en
// /api/v1/... Acepta API_URL con o sin prefijo: si se olvidó, la agrega en vez
// de dejar que el servidor responda 404.
String leerUrlApi([String valor = _urlApiCompilada]) {
  final url = valor.trim();
  if (url.isEmpty) {
    throw StateError(
      'Falta API_URL. Ejecuta la app con '
      '--dart-define=API_URL=http://10.0.2.2:3000/api/v1',
    );
  }

  final sinDiagonal = url.replaceAll(RegExp(r'/+$'), '');
  final raiz = sinDiagonal.endsWith(_prefijoApi)
      ? sinDiagonal.substring(0, sinDiagonal.length - _prefijoApi.length)
      : sinDiagonal.endsWith('/api')
          ? sinDiagonal.substring(0, sinDiagonal.length - '/api'.length)
          : sinDiagonal;
  return '$raiz$_prefijoApi';
}

final proveedorUrlApi = Provider<String>((ref) => leerUrlApi());
