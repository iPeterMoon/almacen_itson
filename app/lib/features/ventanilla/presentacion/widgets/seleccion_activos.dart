import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errores/error_negocio.dart';
import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../../datos/ventanilla_repositorio_api.dart' show minimoCaracteresBusqueda;
import '../entrega_controlador.dart';

// Mensajes de la tabla de activos (HU8, Escenarios 2, 3 y 4).
const mensajeActivoNoEncontrado = 'Activo no encontrado';
const mensajeSinActivos = 'No hay activos registrados.';
const mensajeActivosEscribeParaBuscar = 'Escribe al menos 2 caracteres para buscar';
const mensajeErrorActivos = 'No se pudieron cargar los activos.';
const mensajeActivoNoDisponible = 'El activo no está disponible.';
const mensajeActivoEnPrestamo = 'Este equipo ya está en préstamo.';
const mensajeSinHerramientas = 'No se encontró ninguna herramienta con ese código, nombre o serie';

/// Qué decir cuando la lista de activos llega vacía, según lo que se escribió.
String mensajeActivosVacios(String consulta) {
  final texto = consulta.trim();
  if (texto.isEmpty) return mensajeSinActivos;
  // Con 1 carácter la API no se consulta (pide 2 o más).
  if (texto.length < minimoCaracteresBusqueda) return mensajeActivosEscribeParaBuscar;
  return mensajeActivoNoEncontrado; // Escenario 4
}

/// Texto que se avisa al tocar un activo que no se puede seleccionar.
String mensajeActivoNoSeleccionable(ActivoCatalogo activo) =>
    activo.estado == estadoActivoEnPrestamo ? mensajeActivoEnPrestamo : mensajeActivoNoDisponible;

// Aviso al tocar un activo que no se puede prestar.
void _avisarNoSeleccionable(BuildContext context, ActivoCatalogo activo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensajeActivoNoSeleccionable(activo))));
}

/// Pestaña "Activos" del paso 2 (HU8): tabla "Seleccionados" con los días de
/// préstamo y tabla "Resultados" con el estado de cada equipo y la casilla "Agregar".
/// Usa el mismo formato de fichas que la tabla de materiales (se ve completa en tableta).
/// La búsqueda del campo de arriba (código, nombre o serie) va filtrando la tabla de Resultados.
class SeleccionActivos extends ConsumerWidget {
  const SeleccionActivos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (e.activos.isNotEmpty) ...[
        const _Subtitulo('Seleccionados'),
        ContenedorLista(children: [
          for (var i = 0; i < e.activos.length; i++)
            _FilaSeleccionado(indice: i, item: e.activos[i], controlador: c),
        ]),
        const SizedBox(height: 16),
      ],
      const _Subtitulo('Resultados'),
      const _ResultadosActivos(),
    ]);
  }
}

class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

/// Fila de "Seleccionados": datos del equipo y tiempo de préstamo en días (mínimo 1).
class _FilaSeleccionado extends StatelessWidget {
  const _FilaSeleccionado({required this.indice, required this.item, required this.controlador});

  final int indice;
  final ItemActivo item;
  final EntregaController controlador;

  @override
  Widget build(BuildContext context) {
    final a = item.activo;
    return FilaRegistro(
      indice: indice,
      campos: [
        CampoDato('Valor activo', a.codigo),
        CampoDato('Equipo', a.equipo),
        CampoDato('Modelo', a.modelo),
        CampoDato('N° Serie', a.serie),
        CampoDato(
          'Tiempo de préstamo',
          '${item.dias} días',
          widget: ContadorCompacto(
            valor: item.dias,
            sufijo: 'días',
            etiquetaMenos: 'Disminuir días de ${a.equipo}',
            etiquetaMas: 'Aumentar días de ${a.equipo}',
            // Con 1 día el botón "-" se deshabilita: el préstamo dura al menos un día.
            onMenos: item.dias > 1 ? () => controlador.cambiarDias(a.codigo, item.dias - 1) : null,
            onMas: () => controlador.cambiarDias(a.codigo, item.dias + 1),
          ),
        ),
      ],
    );
  }
}

class _ResultadosActivos extends ConsumerWidget {
  const _ResultadosActivos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);
    final consulta = ref.watch(consultaActivosProvider);

    return ref.watch(activosProvider).when(
          loading: () => const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          // Si el servidor mandó un mensaje (por ejemplo, la sesión expiró), se muestra ese.
          error: (error, _) => AvisoCaja(
              tipo: TipoAviso.error,
              mensaje: error is ErrorNegocio ? error.mensaje : mensajeErrorActivos),
          data: (pagina) => pagina.items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: _SinResultados(mensajeActivosVacios(consulta)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ContenedorLista(children: [
                    for (var i = 0; i < pagina.items.length; i++)
                      _FilaResultado(
                        indice: i,
                        activo: pagina.items[i],
                        agregado: e.activos.any((x) => x.activo.codigo == pagina.items[i].codigo),
                        controlador: c,
                      ),
                  ]),
                  PaginadorTabla(
                    pagina: pagina.pagina,
                    totalPaginas: pagina.totalPaginas,
                    mostrando: pagina.items.length,
                    total: pagina.total,
                    onCambiar: ref.read(paginaActivosProvider.notifier).set,
                  ),
                ]),
        );
  }
}

/// Tabla vacía. Cuando se buscó algo y no hay coincidencias se dan los dos mensajes:
/// "Activo no encontrado" (HU8, Escenario 4) y el detalle de qué se buscó.
class _SinResultados extends StatelessWidget {
  const _SinResultados(this.mensaje);
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(color: Colores.textoSuave);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(mensaje, style: estilo),
      if (mensaje == mensajeActivoNoEncontrado) const Text(mensajeSinHerramientas, style: estilo),
    ]);
  }
}

/// Fila de "Resultados". Disponible: casilla "Agregar". Cualquier otro estado: sin
/// casilla, y al tocarla se avisa por qué no se puede prestar.
class _FilaResultado extends StatelessWidget {
  const _FilaResultado({
    required this.indice,
    required this.activo,
    required this.agregado,
    required this.controlador,
  });

  final int indice;
  final ActivoCatalogo activo;
  final bool agregado;
  final EntregaController controlador;

  @override
  Widget build(BuildContext context) {
    return FilaRegistro(
      indice: indice,
      resaltada: agregado,
      campos: [
        CampoDato('Valor activo', activo.codigo),
        CampoDato('Equipo', activo.equipo),
        CampoDato('Modelo', activo.modelo),
        CampoDato('N° Serie', activo.serie),
        CampoDato('Ubicación', activo.ubicacion),
        CampoDato('Préstamo', EtiquetaEstadoActivo.texto(activo.estado),
            widget: EtiquetaEstadoActivo(activo.estado)),
      ],
      trailing: SizedBox(
        width: 56,
        child: activo.disponible
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  value: agregado,
                  semanticLabel: 'Agregar ${activo.equipo}',
                  onChanged: (_) => controlador.alternarActivo(activo),
                ),
                const Text('Agregar', style: TextStyle(fontSize: 12, color: Colores.textoSuave)),
              ])
            : null,
      ),
      onTap: activo.disponible
          ? () => controlador.alternarActivo(activo)
          : () => _avisarNoSeleccionable(context, activo),
    );
  }
}

/// Etiqueta de color con el estado del activo (columna "Préstamo" del prototipo).
/// Además del color lleva el texto, así no depende solo del color.
class EtiquetaEstadoActivo extends StatelessWidget {
  const EtiquetaEstadoActivo(this.estado, {super.key});

  final String estado;

  static String texto(String estado) => switch (estado) {
        estadoActivoDisponible => 'Disponible',
        estadoActivoEnPrestamo => 'En préstamo',
        estadoActivoEnReparacion => 'En reparación',
        estadoActivoRoboExtravio => 'Robo/Extravío',
        estadoActivoDeBaja => 'De baja',
        _ => estado,
      };

  @override
  Widget build(BuildContext context) {
    final (fondo, color) = switch (estado) {
      estadoActivoDisponible => (Colores.exitoFondo, Colores.exitoOscuro),
      estadoActivoEnPrestamo => (Colores.avisoFondo, Colores.avisoTexto),
      estadoActivoEnReparacion || estadoActivoRoboExtravio => (Colores.peligroFondo, Colores.peligro),
      _ => (Colores.encabezadoTabla, Colores.textoSuave),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16)),
      child: Text(texto(estado),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
