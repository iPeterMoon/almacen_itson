import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errores/error_negocio.dart';

/// Guarda archivos descargados (por ejemplo, el Excel del historial, AI-79) en la
/// carpeta pública Descargas de la tableta, para que el almacenista los encuentre
/// en la app "Archivos". Es una interfaz para poder simularla en las pruebas.
abstract interface class GuardadorArchivos {
  /// Guarda [bytes] con el nombre [nombre] (con extensión, por ejemplo
  /// "historial-entregas-2026-11-25.xlsx") y devuelve el nombre de la carpeta
  /// donde quedó, para avisarle al usuario. Si falla lanza [ErrorNegocio].
  Future<String> guardarEnDescargas({required String nombre, required Uint8List bytes});
}

/// Firma de FileSaver.saveToDownloads con lo que usa la app; se recibe como
/// parámetro para poder probar [GuardadorArchivosDispositivo] sin un dispositivo.
typedef GuardarEnDescargas = Future<String?> Function({
  required String nombreSinExtension,
  required Uint8List bytes,
  required String extension,
  required MimeType tipo,
});

class GuardadorArchivosDispositivo implements GuardadorArchivos {
  GuardadorArchivosDispositivo({GuardarEnDescargas? guardar}) : _guardar = guardar ?? _conFileSaver;

  static const carpetaDescargas = 'Descargas';
  static const codigoNoGuardado = 'ARCHIVO_NO_GUARDADO';
  static const mensajeNoGuardado = 'No se pudo guardar el archivo en Descargas. Intenta de nuevo.';

  final GuardarEnDescargas _guardar;

  // En Android 10 o superior escribe en Descargas con MediaStore, sin pedir
  // permisos; si ya existe un archivo con ese nombre, Android le agrega "(1)".
  static Future<String?> _conFileSaver({
    required String nombreSinExtension,
    required Uint8List bytes,
    required String extension,
    required MimeType tipo,
  }) =>
      FileSaver.instance.saveToDownloads(
        name: nombreSinExtension,
        bytes: bytes,
        fileExtension: extension,
        mimeType: tipo,
      );

  @override
  Future<String> guardarEnDescargas({required String nombre, required Uint8List bytes}) async {
    final (base, extension) = separarExtension(nombre);
    try {
      await _guardar(
        nombreSinExtension: base,
        bytes: bytes,
        extension: extension,
        tipo: extension == 'xlsx' ? MimeType.microsoftExcel : MimeType.other,
      );
      return carpetaDescargas;
    } catch (_) {
      throw const ErrorNegocio(codigoNoGuardado, mensajeNoGuardado);
    }
  }
}

/// Separa "historial.xlsx" en ("historial", "xlsx"). Sin extensión: (nombre, '').
(String, String) separarExtension(String nombre) {
  final punto = nombre.lastIndexOf('.');
  if (punto <= 0 || punto == nombre.length - 1) return (nombre, '');
  return (nombre.substring(0, punto), nombre.substring(punto + 1).toLowerCase());
}

final proveedorGuardadorArchivos =
    Provider<GuardadorArchivos>((ref) => GuardadorArchivosDispositivo());
