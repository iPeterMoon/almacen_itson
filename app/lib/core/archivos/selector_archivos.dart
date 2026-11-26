import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guardador_archivos.dart';

const extensionXlsx = 'xlsx';
const tipoContenidoXlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Archivo que eligió la persona. El contenido se lee hasta que hace falta
/// ([leer]), para poder revisar antes el nombre y el tamaño.
class ArchivoElegido {
  const ArchivoElegido({required this.nombre, required this.leer, this.tamano});

  final String nombre;
  final int? tamano; // bytes; null si el sistema no lo informa
  final Future<Uint8List> Function() leer;
}

/// Único punto de la app que abre el selector de archivos del sistema. Para guardar
/// archivos se usa [GuardadorArchivos] (guardador_archivos.dart).
class SelectorArchivos {
  const SelectorArchivos();

  /// Abre el selector filtrado a .xlsx. Devuelve null si se cancela.
  Future<ArchivoElegido?> elegirXlsx() async {
    final archivo = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [extensionXlsx],
    );
    if (archivo == null) return null;
    return ArchivoElegido(
      nombre: archivo.name,
      tamano: await archivo.length(),
      leer: archivo.readAsBytes,
    );
  }
}

final proveedorSelectorArchivos = Provider<SelectorArchivos>((ref) => const SelectorArchivos());
