import 'package:almacen_itson/core/archivos/guardador_archivos.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);

  test('guarda el Excel en Descargas con su nombre, extensión y tipo, y avisa la carpeta', () async {
    ({String nombre, String extension, MimeType tipo, Uint8List bytes})? recibido;
    final guardador = GuardadorArchivosDispositivo(
      guardar: ({required nombreSinExtension, required bytes, required extension, required tipo}) async {
        recibido = (nombre: nombreSinExtension, extension: extension, tipo: tipo, bytes: bytes);
        return 'content://media/external/downloads/1';
      },
    );

    final carpeta = await guardador.guardarEnDescargas(
      nombre: 'historial-entregas-2026-11-25.xlsx',
      bytes: bytes,
    );

    expect(carpeta, 'Descargas');
    expect(recibido!.nombre, 'historial-entregas-2026-11-25');
    expect(recibido!.extension, 'xlsx');
    expect(recibido!.tipo, MimeType.microsoftExcel);
    expect(recibido!.bytes, bytes);
  });

  test('si el sistema no puede guardar, lanza ErrorNegocio con un mensaje claro', () async {
    final guardador = GuardadorArchivosDispositivo(
      guardar: ({required nombreSinExtension, required bytes, required extension, required tipo}) =>
          throw PlatformException(code: 'DownloadsError', message: 'Failed to save to Downloads'),
    );

    await expectLater(
      guardador.guardarEnDescargas(nombre: 'historial.xlsx', bytes: bytes),
      throwsA(isA<ErrorNegocio>()
          .having((e) => e.codigo, 'codigo', 'ARCHIVO_NO_GUARDADO')
          .having((e) => e.mensaje, 'mensaje', 'No se pudo guardar el archivo en Descargas. Intenta de nuevo.')),
    );
  });

  test('separarExtension divide el nombre y la extensión', () {
    expect(separarExtension('historial-entregas-2026-11-25.xlsx'), ('historial-entregas-2026-11-25', 'xlsx'));
    expect(separarExtension('REPORTE.XLSX'), ('REPORTE', 'xlsx'));
    expect(separarExtension('sin-extension'), ('sin-extension', ''));
    expect(separarExtension('.oculto'), ('.oculto', ''));
    expect(separarExtension('termina.'), ('termina.', ''));
  });
}
