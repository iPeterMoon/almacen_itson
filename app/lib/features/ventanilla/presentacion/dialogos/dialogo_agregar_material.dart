import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errores/error_negocio.dart';
import '../../../../core/tema/tema.dart';
import '../../../../core/widgets/componentes.dart';
import '../../datos/modelos.dart';
import '../entrega_controlador.dart';
import '../validadores.dart';
import 'dialogo_autorizacion.dart';

Future<void> mostrarDialogoAgregarMaterial(
  BuildContext context,
  MaterialCatalogo material,
) => showDialog<void>(
  context: context,
  builder: (_) => DialogoAgregarMaterial(material: material),
);

/// Escenarios 7 (cantidad válida), 8, 9 y 10 (alertas del servidor).
class DialogoAgregarMaterial extends ConsumerStatefulWidget {
  const DialogoAgregarMaterial({super.key, required this.material});
  final MaterialCatalogo material;

  @override
  ConsumerState<DialogoAgregarMaterial> createState() =>
      _DialogoAgregarMaterialState();
}

class _DialogoAgregarMaterialState
    extends ConsumerState<DialogoAgregarMaterial> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController(text: '1');
  // Si el material ya está en la boleta, se propone su misma unidad para poder sumar.
  late String _unidad =
      ref
          .read(entregaControllerProvider)
          .materiales
          .where((x) => x.material.codigo == widget.material.codigo)
          .map((x) => x.unidad)
          .firstOrNull ??
      widget.material.unidades.first;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  double? get _valor =>
      double.tryParse(_cantidad.text.trim().replaceAll(',', '.'));

  void _ajustar(double delta) {
    final nuevo = (_valor ?? 0) + delta;
    if (nuevo > 0) setState(() => _cantidad.text = formatearCantidad(nuevo));
  }

  Future<void> _agregar() async {
    if (!_form.currentState!.validate()) return;
    final cantidad = _valor!;
    final controlador = ref.read(entregaControllerProvider.notifier);
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final alerta = await controlador.agregarMaterial(
        material: widget.material,
        cantidad: cantidad,
        unidad: _unidad,
      );
      if (!mounted) return;
      if (alerta == null) {
        Navigator.pop(context);
        return;
      }
      // Hay restricción: se pide motivo y autorización sobre este mismo diálogo.
      final autorizacion = await showDialog<Autorizacion>(
        context: context,
        builder: (_) => DialogoAutorizacion(
          material: widget.material,
          cantidad: cantidad,
          unidad: _unidad,
          alerta: alerta,
        ),
      );
      if (!mounted) return;
      if (autorizacion != null) {
        controlador.agregarMaterialAutorizado(
          material: widget.material,
          cantidad: cantidad,
          unidad: _unidad,
          autorizacion: autorizacion,
        );
        Navigator.pop(context);
      } else {
        setState(() => _cargando = false);
      }
    } on ErrorNegocio catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted){
        setState(() {
          _cargando = false;
          _error = 'No se pudo conectar con el servidor.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final existente = ref
        .watch(entregaControllerProvider)
        .materiales
        .where((x) => x.material.codigo == m.codigo)
        .firstOrNull;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Agregar Material',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Cantidad (en almacén)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        Text(m.existenciaTexto),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _Dato('Concepto', m.concepto)),
                    Expanded(child: _Dato('Alias', m.alias)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _Dato('Almacén', m.almacen)),
                    Expanded(child: _Dato('Ubicación', m.ubicacion)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cantidad,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        validator: validarCantidad,
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          prefixIcon: IconButton(
                            tooltip: 'Disminuir',
                            onPressed: () => _ajustar(-1),
                            icon: const Icon(Icons.remove),
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Aumentar',
                            onPressed: () => _ajustar(1),
                            icon: const Icon(Icons.add),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CampoSelector<String>(
                        etiqueta: 'Unidad de medida',
                        valor: _unidad,
                        items: [
                          for (final u in m.unidades)
                            DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (v) =>
                            setState(() => _unidad = v ?? _unidad),
                      ),
                    ),
                  ],
                ),
                if (existente != null) ...[
                  const SizedBox(height: 12),
                  AvisoCaja(
                    tipo: TipoAviso.info,
                    mensaje:
                        'Ya hay ${existente.cantidadTexto} en la boleta. La cantidad que agregues se sumará.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AvisoCaja(tipo: TipoAviso.error, mensaje: _error!),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cargando
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _cargando ? null : _agregar,
                        child: _cargando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Agregar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        etiqueta,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
      const SizedBox(height: 2),
      Text(valor, style: const TextStyle(color: Colores.texto)),
    ],
  );
}
