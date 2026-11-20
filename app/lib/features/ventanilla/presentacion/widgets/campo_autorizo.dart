import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/validacion/limites_texto.dart';
import '../../../../core/validacion/solo_letras.dart';
import '../entrega_controlador.dart';

const etiquetaAutorizo = 'Autorizó (Opcional)';
const ayudaAutorizo =
    'Solo letras y espacios, sin números ni signos (máx. 200 caracteres).';

/// Campo opcional de "Autorizó", compartido por el paso del solicitante y el
/// de firmas. Sugiere supervisores del campus, pero acepta texto libre para
/// autorizaciones externas. Si la lista no se puede cargar, sigue funcionando
/// como campo libre.
class CampoAutorizo extends ConsumerStatefulWidget {
  const CampoAutorizo({super.key});

  @override
  ConsumerState<CampoAutorizo> createState() => _CampoAutorizoState();
}

class _CampoAutorizoState extends ConsumerState<CampoAutorizo> {
  late final TextEditingController _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = TextEditingController(
      text: ref.read(entregaControllerProvider).autorizoNombre,
    );
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardado = ref.watch(entregaControllerProvider).autorizoNombre;
    if (_controlador.text != guardado) _controlador.text = guardado;
    final notificador = ref.read(entregaControllerProvider.notifier);
    final decoracion = InputDecoration(
      labelText: etiquetaAutorizo,
      hintText: 'Nombre de quien autorizó',
      helperText: ayudaAutorizo,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    void guardar(String valor) {
      final limpio = soloLetras(valor);
      _controlador.text = limpio;
      notificador.setAutorizoNombre(limpio);
    }

    Widget campoLibre() {
      return TextField(
        controller: _controlador,
        decoration: decoracion,
        maxLength: limiteNombre,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        inputFormatters: formattersSoloLetras,
        onChanged: guardar,
      );
    }

    Widget campoConSugerencias(List<String> nombres) {
      return Autocomplete<String>(
        optionsBuilder: (texto) {
          final consulta = soloLetras(texto.text.trim().toLowerCase());
          if (consulta.isEmpty) return const Iterable<String>.empty();
          return nombres.where((nombre) => soloLetras(nombre.toLowerCase()).contains(consulta));
        },
        onSelected: (nombre) {
          guardar(nombre);
          _controlador.selection = TextSelection.fromPosition(
            TextPosition(offset: _controlador.text.length),
          );
        },
        fieldViewBuilder: (context, controlador, focusNode, alEnfocar) {
          // Autocomplete maneja su propio controlador: lo mantenemos igual que
          // el nuestro para que las sugerencias y la boleta no se separen.
          if (controlador.text != _controlador.text) {
            controlador.text = _controlador.text;
          }
          return TextField(
            controller: controlador,
            focusNode: focusNode,
            onTap: alEnfocar,
            decoration: decoracion,
            maxLength: limiteNombre,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            inputFormatters: formattersSoloLetras,
            onChanged: (valor) {
              final limpio = soloLetras(valor);
              if (limpio != valor) controlador.text = limpio;
              guardar(limpio);
            },
          );
        },
      );
    }

    final sugerencias = ref.watch(supervisoresProvider);
    return sugerencias.when(
      data: (lista) => campoConSugerencias(lista.map((s) => s.nombre).toList()),
      loading: campoLibre,
      error: (_, _) => campoLibre(),
    );
  }
}
