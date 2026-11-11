import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../entrega_controlador.dart';

/// Paso 1. Escenarios 2 (solicitante no registrado), 3 y 4 (número de solicitud opcional).
class PasoSolicitante extends ConsumerStatefulWidget {
  const PasoSolicitante({super.key});

  @override
  ConsumerState<PasoSolicitante> createState() => _PasoSolicitanteState();
}

class _PasoSolicitanteState extends ConsumerState<PasoSolicitante> {
  Timer? _espera;
  late final TextEditingController _nombre;
  late final TextEditingController _unidad;
  late final TextEditingController _numero;

  @override
  void initState() {
    super.initState();
    final e = ref.read(entregaControllerProvider);
    _nombre = TextEditingController(text: e.nombreSinRegistro);
    _unidad = TextEditingController(text: e.unidadSinRegistro);
    _numero = TextEditingController(text: e.numeroSolicitud);
  }

  @override
  void dispose() {
    _espera?.cancel();
    _nombre.dispose();
    _unidad.dispose();
    _numero.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    _espera?.cancel();
    // Espera de ~300 ms antes de consultar (regla de interfaz del equipo).
    _espera = Timer(const Duration(milliseconds: 300),
        () => ref.read(consultaSolicitantesProvider.notifier).set(texto));
  }

  @override
  Widget build(BuildContext context) {
    final e = ref.watch(entregaControllerProvider);
    final c = ref.read(entregaControllerProvider.notifier);
    final resultados = ref.watch(solicitantesProvider);
    final autorizadores = ref.watch(autorizadoresProvider);
    final s = e.solicitante;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        TarjetaSeccion(
          titulo: 'Buscar solicitante',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              enabled: !e.sinRegistro,
              onChanged: _buscar,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre del solicitante',
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (!e.sinRegistro)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => c.usarSinRegistro(true),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colores.infoFondo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(children: [
                    CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person_add_alt, color: Colores.primario)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Usar solicitante sin registro',
                            style: TextStyle(color: Colores.primario, fontWeight: FontWeight.w700)),
                        Text('Ingresa nombre y unidad/campus para solicitantes no registrados.',
                            style: TextStyle(color: Colores.textoSuave, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              ),
            if (e.sinRegistro) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: Colores.borde)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Solicitante no registrado',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _nombre,
                      onChanged: c.setNombreSinRegistro,
                      decoration: const InputDecoration(labelText: 'Nombre')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _unidad,
                      onChanged: c.setUnidadSinRegistro,
                      decoration: const InputDecoration(labelText: 'Unidad/Campus')),
                  const SizedBox(height: 4),
                  TextButton(
                      onPressed: () => c.usarSinRegistro(false),
                      child: const Text('Buscar en el registro de personal')),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 12),
              resultados.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
                error: (_, __) => const AvisoCaja(
                    tipo: TipoAviso.error, mensaje: 'No se pudo cargar el personal. Intenta de nuevo.'),
                data: (lista) => lista.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Sin resultados. Puedes usar un solicitante sin registro.',
                            style: TextStyle(color: Colores.textoSuave)))
                    : Column(children: [
                        const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Selecciona un solicitante para continuar.',
                                style: TextStyle(color: Colores.textoSuave))),
                        for (var i = 0; i < lista.length; i++)
                          ListTile(
                            minTileHeight: 56,
                            tileColor: i.isOdd ? Colores.filaAlterna : null,
                            selected: s?.id == lista[i].id,
                            selectedTileColor: Colores.infoFondo,
                            title: Text(lista[i].nombre,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${lista[i].dependencia} · ${lista[i].tipo} · ${lista[i].zona}'),
                            trailing: s?.id == lista[i].id
                                ? const Icon(Icons.check_circle, color: Colores.primario)
                                : null,
                            onTap: () => c.seleccionarSolicitante(lista[i]),
                          ),
                      ]),
              ),
              if (s != null) ...[
                const SizedBox(height: 16),
                const Text('Información del trabajador seleccionado',
                    style: TextStyle(color: Colores.textoSuave)),
                FilaInfo('Trabajador:', s.nombre, negrita: true),
                FilaInfo('Área de trabajo:', s.areaTrabajo ?? '-'),
                FilaInfo('Área de trabajo 2:', s.areaTrabajo2 ?? '-'),
                FilaInfo('Dependencia:', s.dependencia),
                FilaInfo('Tipo:', s.tipo),
              ],
            ],
          ]),
        ),
        const SizedBox(height: 12),
        TarjetaSeccion(
          titulo: 'Datos adicionales',
          subtitulo: 'Información opcional de la solicitud',
          child: LayoutBuilder(builder: (context, caja) {
            final autorizo = autorizadores.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('No se pudo cargar la lista.'),
              data: (lista) => CampoSelector<String>(
                etiqueta: 'Autorizó (Opcional)',
                valor: e.autorizoId,
                items: [for (final a in lista) DropdownMenuItem(value: a.id, child: Text(a.nombre))],
                onChanged: c.setAutorizo,
              ),
            );
            final numero = TextField(
              controller: _numero,
              onChanged: c.setNumeroSolicitud,
              decoration: const InputDecoration(
                  labelText: 'No. Solicitud (Opcional)', hintText: 'Ej. OT-9981'),
            );
            return caja.maxWidth > 520
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: autorizo),
                    const SizedBox(width: 12),
                    Expanded(child: numero),
                  ])
                : Column(children: [autorizo, const SizedBox(height: 12), numero]);
          }),
        ),
      ],
    );
  }
}
