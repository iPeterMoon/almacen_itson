import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../dialogos/dialogo_agregar_material.dart';
import '../dialogos/dialogo_lista_materiales.dart';
import '../entrega_controlador.dart';

/// Paso 2: "Selecciona material o equipo a entregar".
/// Materiales: búsqueda + "Más comunes"/"Todos" + filtros de categoría, tipo y almacén.
class PasoMateriales extends ConsumerStatefulWidget {
  const PasoMateriales({super.key});

  @override
  ConsumerState<PasoMateriales> createState() => _PasoMaterialesState();
}

class _PasoMaterialesState extends ConsumerState<PasoMateriales> {
  int _pestana = 0;
  Timer? _espera;

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 300), () {
      if (_pestana == 0) {
        ref.read(filtroMaterialesProvider.notifier).setConsulta(texto);
      } else {
        ref.read(consultaActivosProvider.notifier).set(texto);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = ref.watch(entregaControllerProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => mostrarDialogoListaMateriales(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 56),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Badge(
              isLabelVisible: e.totalPartidas > 0,
              label: Text('${e.totalPartidas}'),
              child: const Icon(Icons.assignment_turned_in_outlined, size: 28),
            ),
            label: const Text('Materiales a entregar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        TarjetaSeccion(
          titulo: 'Selecciona material o equipo a entregar',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: BotonPestana(
                      texto: 'Materiales',
                      seleccionado: _pestana == 0,
                      onTap: () => setState(() => _pestana = 0))),
              const SizedBox(width: 12),
              Expanded(
                  child: BotonPestana(
                      texto: 'Activos',
                      seleccionado: _pestana == 1,
                      onTap: () => setState(() => _pestana = 1))),
            ]),
            const SizedBox(height: 12),
            TextField(
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: _pestana == 0
                    ? 'Buscar por código o concepto/alias del material'
                    : 'Buscar por código, equipo o número de serie',
                suffixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_pestana == 0) const _FiltrosMateriales(),
            if (_pestana == 0) const _ResultadosMateriales() else const _ResultadosActivos(),
          ]),
        ),
      ],
    );
  }
}

class _FiltrosMateriales extends ConsumerWidget {
  const _FiltrosMateriales();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroMaterialesProvider);
    final notif = ref.read(filtroMaterialesProvider.notifier);
    final opciones = ref.watch(opcionesFiltrosProvider);

    Widget selector(String etiqueta, String? valor, List<String> lista, ValueChanged<String?> alCambiar) =>
        SelectorCompacto<String?>(
          etiqueta: etiqueta,
          valor: valor,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            for (final o in lista) DropdownMenuItem<String?>(value: o, child: Text(o)),
          ],
          onChanged: alCambiar,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Filtrar por:', style: TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        PildoraFiltro(
            texto: 'Más comunes',
            seleccionada: filtro.soloComunes,
            onTap: () => notif.setSoloComunes(true)),
        const SizedBox(width: 8),
        PildoraFiltro(
            texto: 'Todos',
            seleccionada: !filtro.soloComunes,
            onTap: () => notif.setSoloComunes(false)),
      ]),
      const SizedBox(height: 16),
      opciones.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => const AvisoCaja(
            tipo: TipoAviso.error, mensaje: 'No se pudieron cargar los filtros.'),
        data: (o) => Wrap(spacing: 12, runSpacing: 12, children: [
          selector('Categoría', filtro.categoria, o.categorias, notif.setCategoria),
          selector('Tipo', filtro.tipo, o.tipos, notif.setTipo),
          selector('Almacén', filtro.almacen, o.almacenes, notif.setAlmacen),
        ]),
      ),
      const SizedBox(height: 16),
      const Text('Resultados', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
    ]);
  }
}

class _ResultadosMateriales extends ConsumerWidget {
  const _ResultadosMateriales();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(entregaControllerProvider);
    return ref.watch(materialesProvider).when(
          loading: () => const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (_, __) =>
              const AvisoCaja(tipo: TipoAviso.error, mensaje: 'No se pudo cargar el catálogo.'),
          data: (pagina) => pagina.items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No hay materiales con ese criterio.',
                      style: TextStyle(color: Colores.textoSuave)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TablaDatos(
                    encabezados: const [
                      'Código', 'Concepto', 'Alias', 'Categoría', 'Almacén', 'Existencia'
                    ],
                    flex: const [2, 3, 3, 3, 3, 3],
                    filas: [
                      for (final m in pagina.items)
                        [m.codigo, m.concepto, m.alias, m.categoria, m.almacen, m.existenciaTexto]
                    ],
                    // Las filas ya agregadas a la boleta se resaltan.
                    resaltada: (i) =>
                        e.materiales.any((x) => x.material.codigo == pagina.items[i].codigo),
                    onTap: (i) => mostrarDialogoAgregarMaterial(context, pagina.items[i]),
                  ),
                  PaginadorTabla(
                    pagina: pagina.pagina,
                    totalPaginas: pagina.totalPaginas,
                    mostrando: pagina.items.length,
                    total: pagina.total,
                    onCambiar: ref.read(paginaMaterialesProvider.notifier).set,
                  ),
                ]),
        );
  }
}

class _ResultadosActivos extends ConsumerWidget {
  const _ResultadosActivos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);
    return ref.watch(activosProvider).when(
          loading: () => const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (_, __) =>
              const AvisoCaja(tipo: TipoAviso.error, mensaje: 'No se pudo cargar los activos.'),
          data: (lista) => lista.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No hay activos con ese criterio.',
                      style: TextStyle(color: Colores.textoSuave)))
              : Column(children: [
                  for (var i = 0; i < lista.length; i++)
                    ListTile(
                      minTileHeight: 64,
                      tileColor: i.isOdd ? Colores.filaAlterna : null,
                      title: Text('${lista[i].codigo} · ${lista[i].equipo}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${lista[i].modelo} · Serie ${lista[i].serie}'),
                      trailing: e.activos.any((a) => a.activo.codigo == lista[i].codigo)
                          ? const Icon(Icons.check_circle, color: Colores.exitoOscuro)
                          : const Icon(Icons.add_circle_outline, color: Colores.primario),
                      onTap: () {
                        c.agregarActivo(lista[i]);
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${lista[i].equipo} agregado (1 día).')));
                      },
                    ),
                ]),
        );
  }
}
