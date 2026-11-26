import 'dart:async';
import 'dart:typed_data';

import 'package:almacen_itson/core/archivos/guardador_archivos.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/ventanilla/datos/historial_entregas_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/modelos.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/exportar_historial_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/historial_entregas_controlador.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _excel = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);

// Repositorio falso: el historial responde vacío y exportar guarda la búsqueda
// con la que se llamó. Con [pendiente] la descarga no termina hasta completarlo.
class _RepoFalso extends HistorialEntregasRepositorio {
  _RepoFalso({this.total = 3, this.error}) : super(Dio());

  final int total;
  final ErrorNegocio? error;
  final List<String> consultasExportadas = [];
  Completer<void>? pendiente;

  @override
  Future<Pagina<EntregaHistorial>> listar({
    required int pagina,
    required int porPagina,
    String consulta = '',
    DateTime? desde,
    DateTime? hasta,
  }) async =>
      Pagina(items: const [], total: 0, pagina: pagina, porPagina: porPagina);

  @override
  Future<ArchivoHistorial> exportar({String consulta = ''}) async {
    consultasExportadas.add(consulta);
    await pendiente?.future;
    if (error != null) throw error!;
    return ArchivoHistorial(
        nombre: 'historial-entregas-2026-11-25.xlsx', bytes: _excel, total: total);
  }
}

class _GuardadorFalso implements GuardadorArchivos {
  _GuardadorFalso({this.error});

  final ErrorNegocio? error;
  final List<String> nombres = [];
  final List<Uint8List> archivos = [];

  @override
  Future<String> guardarEnDescargas({required String nombre, required Uint8List bytes}) async {
    if (error != null) throw error!;
    nombres.add(nombre);
    archivos.add(bytes);
    return 'Descargas';
  }
}

({ProviderContainer c, _RepoFalso repo, _GuardadorFalso guardador}) _crear({
  _RepoFalso? repo,
  _GuardadorFalso? guardador,
}) {
  final r = repo ?? _RepoFalso();
  final g = guardador ?? _GuardadorFalso();
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      proveedorHistorialEntregasRepositorio.overrideWithValue(r),
      proveedorGuardadorArchivos.overrideWithValue(g),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, repo: r, guardador: g);
}

void main() {
  test('antes de exportar no hay resultado ni carga', () {
    final (:c, repo: _, guardador: _) = _crear();

    final estado = c.read(exportarHistorialProvider);

    expect(estado.isLoading, isFalse);
    expect(estado.value, isNull);
  });

  test('exporta con la búsqueda activa del historial y guarda el archivo en Descargas', () async {
    final (:c, :repo, :guardador) = _crear();
    await c.read(historialEntregasProvider.future);
    await c.read(historialEntregasProvider.notifier).buscar('  jose avila ');

    await c.read(exportarHistorialProvider.notifier).exportar();

    // La misma búsqueda que filtra la tabla (sin espacios a los lados).
    expect(repo.consultasExportadas, ['jose avila']);
    expect(guardador.nombres, ['historial-entregas-2026-11-25.xlsx']);
    expect(guardador.archivos.single, _excel);
    final resultado = c.read(exportarHistorialProvider).value!;
    expect(resultado.nombre, 'historial-entregas-2026-11-25.xlsx');
    expect(resultado.carpeta, 'Descargas');
    expect(resultado.total, 3);
    expect(resultado.recortado, isFalse);
  });

  test('sin búsqueda exporta el historial completo', () async {
    final (:c, :repo, guardador: _) = _crear();
    await c.read(historialEntregasProvider.future);

    await c.read(exportarHistorialProvider.notifier).exportar();

    expect(repo.consultasExportadas, ['']);
  });

  test('al borrar la búsqueda vuelve a exportar todo', () async {
    final (:c, :repo, guardador: _) = _crear();
    final historial = c.read(historialEntregasProvider.notifier);
    await c.read(historialEntregasProvider.future);
    await historial.buscar('juan');
    await historial.buscar('');

    await c.read(exportarHistorialProvider.notifier).exportar();

    expect(repo.consultasExportadas, ['']);
  });

  test('avisa si el archivo se cortó en el tope de filas', () async {
    final (:c, repo: _, guardador: _) = _crear(repo: _RepoFalso(total: 1500));
    await c.read(historialEntregasProvider.future);

    await c.read(exportarHistorialProvider.notifier).exportar();

    final resultado = c.read(exportarHistorialProvider).value!;
    expect(resultado.total, 1500);
    expect(resultado.recortado, isTrue);
  });

  test('mientras exporta está cargando y un segundo toque no inicia otra descarga', () async {
    final repo = _RepoFalso()..pendiente = Completer<void>();
    final (:c, repo: _, :guardador) = _crear(repo: repo);
    await c.read(historialEntregasProvider.future);
    final exportar = c.read(exportarHistorialProvider.notifier);

    final primera = exportar.exportar();
    expect(c.read(exportarHistorialProvider).isLoading, isTrue);
    await exportar.exportar();

    repo.pendiente!.complete();
    await primera;
    expect(repo.consultasExportadas, hasLength(1));
    expect(guardador.nombres, hasLength(1));
    expect(c.read(exportarHistorialProvider).isLoading, isFalse);
  });

  test('si el servidor falla queda el error y no se guarda nada', () async {
    const fallo = ErrorNegocio('PETICION_INVALIDA', 'La petición tiene datos inválidos.', estadoHttp: 400);
    final (:c, repo: _, :guardador) = _crear(repo: _RepoFalso(error: fallo));
    await c.read(historialEntregasProvider.future);

    await c.read(exportarHistorialProvider.notifier).exportar();

    final estado = c.read(exportarHistorialProvider);
    expect(estado.hasError, isTrue);
    expect((estado.error! as ErrorNegocio).mensaje, 'La petición tiene datos inválidos.');
    expect(guardador.nombres, isEmpty);
  });

  test('si no se puede guardar en Descargas queda ese error', () async {
    const fallo = ErrorNegocio(GuardadorArchivosDispositivo.codigoNoGuardado,
        GuardadorArchivosDispositivo.mensajeNoGuardado);
    final (:c, repo: _, guardador: _) = _crear(guardador: _GuardadorFalso(error: fallo));
    await c.read(historialEntregasProvider.future);

    await c.read(exportarHistorialProvider.notifier).exportar();

    final estado = c.read(exportarHistorialProvider);
    expect(estado.hasError, isTrue);
    expect((estado.error! as ErrorNegocio).codigo, 'ARCHIVO_NO_GUARDADO');
  });

  test('después de un error se puede volver a exportar', () async {
    final repo = _RepoFalso(error: const ErrorNegocio('SIN_CONEXION', 'Sin conexión.'));
    final (:c, repo: _, guardador: _) = _crear(repo: repo);
    await c.read(historialEntregasProvider.future);
    final exportar = c.read(exportarHistorialProvider.notifier);

    await exportar.exportar();
    await exportar.exportar();

    expect(repo.consultasExportadas, hasLength(2));
  });
}
