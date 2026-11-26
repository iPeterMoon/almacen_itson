import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/archivos/guardador_archivos.dart';
import '../datos/historial_entregas_repositorio.dart';
import 'historial_entregas_controlador.dart';

/// Resultado de exportar el historial a Excel (AI-79): qué archivo se guardó y dónde.
class ExportacionHistorial {
  const ExportacionHistorial({
    required this.nombre,
    required this.carpeta,
    required this.total,
    required this.recortado,
  });

  final String nombre;
  final String carpeta;

  /// Boletas que cumplen la búsqueda (puede ser mayor que las filas del archivo).
  final int total;

  /// true si el archivo trae solo las primeras [ArchivoHistorial.maximoFilas].
  final bool recortado;
}

/// HU11 (AI-79): exporta a Excel las boletas que muestra el historial, con la
/// búsqueda activa, y las guarda en Descargas.
///
/// Estado: `AsyncData(null)` antes de exportar; `AsyncLoading` mientras descarga y
/// guarda (la pantalla desactiva el botón); `AsyncData` con el resultado para avisar
/// dónde quedó el archivo; `AsyncError` con el error para mostrar su mensaje.
class ExportarHistorialControlador extends AsyncNotifier<ExportacionHistorial?> {
  @override
  FutureOr<ExportacionHistorial?> build() => null;

  Future<void> exportar() async {
    // Un segundo toque mientras se exporta no inicia otra descarga.
    if (state.isLoading) return;
    // La misma búsqueda con la que se pidió la tabla que se ve en pantalla.
    final consulta = ref.read(historialEntregasProvider.notifier).consulta;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final archivo =
          await ref.read(proveedorHistorialEntregasRepositorio).exportar(consulta: consulta);
      final carpeta = await ref
          .read(proveedorGuardadorArchivos)
          .guardarEnDescargas(nombre: archivo.nombre, bytes: archivo.bytes);
      return ExportacionHistorial(
        nombre: archivo.nombre,
        carpeta: carpeta,
        total: archivo.total,
        recortado: archivo.recortado,
      );
    });
  }
}

final exportarHistorialProvider =
    AsyncNotifierProvider<ExportarHistorialControlador, ExportacionHistorial?>(
        ExportarHistorialControlador.new);
