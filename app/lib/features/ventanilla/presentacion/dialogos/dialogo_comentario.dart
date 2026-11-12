import 'package:flutter/material.dart';

/// Escenario 5: comentario por material/activo. Devuelve el texto o null si se cancela.
Future<String?> mostrarDialogoComentario(
  BuildContext context, {
  required String nombre,
  required String detalle,
  String? inicial,
}) {
  final texto = TextEditingController(text: inicial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Agregar un comentario al material',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text.rich(TextSpan(children: [
                TextSpan(text: nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '  $detalle'),
              ])),
              const SizedBox(height: 12),
              TextField(
                controller: texto,
                autofocus: true,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'Escribe aquí tu comentario...'),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                const SizedBox(width: 12),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, texto.text), child: const Text('Confirmar')),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}
