import 'package:flutter/material.dart';
import '../tema/tema.dart';

/// Tarjeta blanca con borde redondeado y título opcional (patrón repetido en el Figma).
class TarjetaSeccion extends StatelessWidget {
  const TarjetaSeccion({super.key, this.titulo, this.subtitulo, required this.child});

  final String? titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colores.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null)
            Text(titulo!,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, color: Colores.texto)),
          if (subtitulo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitulo!, style: const TextStyle(color: Colores.textoSuave)),
            ),
          if (titulo != null || subtitulo != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum TipoAviso { advertencia, error, info }

/// Caja de aviso (amarilla = advertencia, roja = error, azul = info).
class AvisoCaja extends StatelessWidget {
  const AvisoCaja({super.key, required this.tipo, this.titulo, required this.mensaje});

  final TipoAviso tipo;
  final String? titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = switch (tipo) {
      TipoAviso.advertencia => (Colores.avisoFondo, Colores.avisoTexto),
      TipoAviso.error => (Colores.peligroFondo, Colores.peligro),
      TipoAviso.info => (Colores.infoFondo, Colores.primario),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null)
            Text(titulo!, style: TextStyle(color: texto, fontWeight: FontWeight.w700)),
          Text(mensaje, style: TextStyle(color: texto)),
        ],
      ),
    );
  }
}

/// Lista desplegable con etiqueta (usa DropdownButton para no depender de la versión de Flutter).
class CampoSelector<T> extends StatelessWidget {
  const CampoSelector({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.items,
    required this.onChanged,
    this.hint = 'Selecciona',
  });

  final String etiqueta;
  final T? valor;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: etiqueta),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: valor,
          hint: Text(hint),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class FilaInfo extends StatelessWidget {
  const FilaInfo(this.etiqueta, this.valor, {super.key, this.negrita = false});

  final String etiqueta;
  final String valor;
  final bool negrita;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colores.borde))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              flex: 2,
              child: Text(etiqueta, style: const TextStyle(color: Colores.textoSuave))),
          Expanded(
              flex: 3,
              child: Text(valor,
                  style: TextStyle(fontWeight: negrita ? FontWeight.w700 : FontWeight.w400))),
        ],
      ),
    );
  }
}
