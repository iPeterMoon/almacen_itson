import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/archivos/selector_archivos.dart';
import '../../../core/errores/error_negocio.dart';
import '../datos/importacion_entregas_repositorio.dart';
import 'historial_entregas_controlador.dart';

/// Avance de la importación. [progreso] va de 0 a 1 mientras se envía el archivo;
/// en 1 ya se envió y el servidor lo está validando.
class EstadoImportacion {
  const EstadoImportacion({this.enviando = false, this.progreso = 0});

  final bool enviando;
  final double progreso;
}

/// HU11 (escenario 6): envía el Excel de entregas anteriores y, si se importó,
/// recarga el historial.
class ImportacionEntregasControlador extends Notifier<EstadoImportacion> {
  /// Mismo límite que el servidor. Se revisa aquí para no subir un archivo que
  /// se va a rechazar; el servidor lo valida de todos modos.
  static const maximoBytes = 5 * 1024 * 1024;

  static const errorExtension =
      ErrorNegocio('TIPO_NO_SOPORTADO', 'Solo se aceptan archivos con extensión .xlsx.');
  static const errorTamano =
      ErrorNegocio('ARCHIVO_MUY_GRANDE', 'El archivo supera el máximo de 5 MB.');

  @override
  EstadoImportacion build() => const EstadoImportacion();

  /// Devuelve null si ya había una importación en curso. Las filas inválidas vienen en
  /// el resultado; cualquier otro fallo se lanza como [ErrorNegocio].
  Future<ResultadoImportacion?> importar(ArchivoElegido archivo) async {
    if (state.enviando) return null;
    // En Android el filtro del selector no siempre impide elegir otro tipo.
    if (!archivo.nombre.toLowerCase().endsWith('.$extensionXlsx')) throw errorExtension;
    if ((archivo.tamano ?? 0) > maximoBytes) throw errorTamano;

    state = const EstadoImportacion(enviando: true);
    try {
      final contenido = await archivo.leer();
      if (contenido.length > maximoBytes) throw errorTamano;
      final resultado = await ref.read(proveedorImportacionEntregasRepositorio).importar(
            nombre: archivo.nombre,
            contenido: contenido,
            alProgresar: (f) => state = EstadoImportacion(enviando: true, progreso: f),
          );
      if (resultado.exitosa) {
        // Sin await: la tabla muestra su propio indicador mientras recarga.
        ref.read(historialEntregasProvider.notifier).recargar().ignore();
      }
      return resultado;
    } finally {
      state = const EstadoImportacion();
    }
  }
}

final importacionEntregasProvider =
    NotifierProvider<ImportacionEntregasControlador, EstadoImportacion>(
        ImportacionEntregasControlador.new);
