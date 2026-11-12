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

/// Tabla con encabezado y filas alternadas (formato del prototipo).
/// SIEMPRE se ve completa, sin desplazamiento horizontal: las columnas se reparten el ancho
/// disponible y el texto largo baja a otra línea. En pantallas angostas la letra se reduce un poco.
class TablaDatos extends StatelessWidget {
  const TablaDatos({
    super.key,
    required this.encabezados,
    required this.flex,
    required this.filas,
    this.onTap,
    this.resaltada,
    this.primeraNegrita = false,
  });

  final List<String> encabezados;
  final List<int> flex; // ancho relativo de cada columna
  final List<List<String>> filas;
  final void Function(int fila)? onTap;
  final bool Function(int fila)? resaltada;
  final bool primeraNegrita;

  Widget _fila(List<String> celdas, bool compacto, {Color? color, bool encabezado = false}) =>
      Container(
        color: color,
        constraints: const BoxConstraints(minHeight: 48),
        padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var k = 0; k < celdas.length; k++)
            Expanded(
              flex: flex[k],
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(celdas[k],
                    softWrap: true,
                    style: TextStyle(
                        fontSize: compacto ? 12.5 : 14,
                        color: Colores.texto,
                        fontWeight: (encabezado || (k == 0 && primeraNegrita))
                            ? FontWeight.w700
                            : FontWeight.w400)),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colores.borde),
      ),
      child: LayoutBuilder(builder: (context, caja) {
        final compacto = caja.maxWidth < 600;
        return Column(children: [
          _fila(encabezados, compacto, color: Colores.encabezadoTabla, encabezado: true),
          for (var i = 0; i < filas.length; i++)
            InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              child: _fila(
                filas[i],
                compacto,
                color: (resaltada?.call(i) ?? false)
                    ? Colores.infoFondo
                    : (i.isOdd ? Colores.filaAlterna : Colors.white),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Pie de tabla del prototipo: "Mostrando N de M registros" a la izquierda y
/// Anterior · páginas (la actual en un círculo claro) · … · Siguiente a la derecha.
class PaginadorTabla extends StatelessWidget {
  const PaginadorTabla({
    super.key,
    required this.pagina,
    required this.totalPaginas,
    required this.mostrando,
    required this.total,
    required this.onCambiar,
  });

  final int pagina; // empieza en 1
  final int totalPaginas;
  final int mostrando;
  final int total;
  final ValueChanged<int> onCambiar;

  /// null representa los puntos suspensivos.
  static List<int?> paginasVisibles(int actual, int total) {
    if (total <= 5) return [for (var i = 1; i <= total; i++) i];
    final conjunto = <int>{1, total, actual - 1, actual, actual + 1}
      ..removeWhere((p) => p < 1 || p > total);
    final orden = conjunto.toList()..sort();
    final resultado = <int?>[];
    for (var i = 0; i < orden.length; i++) {
      if (i > 0 && orden[i] - orden[i - 1] > 1) resultado.add(null);
      resultado.add(orden[i]);
    }
    return resultado;
  }

  Widget _navegar(String texto, VoidCallback? alPulsar) => TextButton(
        onPressed: alPulsar,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: Colores.texto,
          disabledForegroundColor: Colores.deshabilitado,
        ),
        child: Text(texto),
      );

  Widget _numero(int p) {
    final actual = p == pagina;
    return Semantics(
      button: true,
      selected: actual,
      label: 'Página $p',
      child: InkResponse(
        onTap: actual ? null : () => onCambiar(p),
        radius: 24,
        child: SizedBox(
          width: 40,
          height: 48,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: actual ? Colores.paginaActual : null, shape: BoxShape.circle),
              child: Text('$p',
                  style: TextStyle(
                      color: Colores.texto,
                      fontWeight: actual ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navegacion = Row(mainAxisSize: MainAxisSize.min, children: [
      _navegar('Anterior', pagina > 1 ? () => onCambiar(pagina - 1) : null),
      for (final p in paginasVisibles(pagina, totalPaginas))
        if (p == null)
          const SizedBox(
              width: 32,
              child: Center(child: Text('…', style: TextStyle(fontWeight: FontWeight.w700))))
        else
          _numero(p),
      _navegar('Siguiente', pagina < totalPaginas ? () => onCambiar(pagina + 1) : null),
    ]);
    final leyenda = Text('Mostrando $mostrando de $total registros',
        style: const TextStyle(color: Colores.texto, fontSize: 13));

    // Prototipo: leyenda a la izquierda y navegación pegada al borde derecho, en la misma fila.
    // La leyenda ocupa el espacio sobrante (Expanded) y la navegación mantiene su ancho natural,
    // así queda a la derecha. En pantallas muy angostas (< 520) se apilan: leyenda arriba y
    // navegación alineada a la derecha debajo.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(builder: (context, caja) {
        if (caja.maxWidth >= 520) {
          return Row(children: [Expanded(child: leyenda), navegacion]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          leyenda,
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: navegacion),
          ),
        ]);
      }),
    );
  }
}

/// Botón de pestaña del prototipo: seleccionado = azul lleno; no seleccionado = blanco con borde.
class BotonPestana extends StatelessWidget {
  const BotonPestana({super.key, required this.texto, required this.seleccionado, required this.onTap});
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: seleccionado,
      child: Material(
        color: seleccionado ? Colores.primario : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: seleccionado ? Colores.primario : Colores.borde),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(texto,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: seleccionado ? Colors.white : Colores.texto)),
          ),
        ),
      ),
    );
  }
}

/// Píldora de filtro ("Más comunes" / "Todos"): seleccionada = azul claro con borde azul.
class PildoraFiltro extends StatelessWidget {
  const PildoraFiltro({super.key, required this.texto, required this.seleccionada, required this.onTap});
  final String texto;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: seleccionada,
      child: Material(
        color: seleccionada ? const Color(0xFFDBEAFE) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: seleccionada ? const Color(0xFF93C5FD) : Colores.borde),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Text(texto,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: seleccionada ? Colores.primario : Colores.texto)),
          ),
        ),
      ),
    );
  }
}

/// Filtro desplegable del prototipo: etiqueta arriba y campo compacto con flecha abajo.
class SelectorCompacto<T> extends StatelessWidget {
  const SelectorCompacto({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.items,
    required this.onChanged,
    this.hint = 'Todos',
    this.ancho = 170,
  });

  final String etiqueta;
  final T? valor;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hint;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etiqueta, style: const TextStyle(color: Colores.texto)),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colores.borde),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: valor,
              hint: Text(hint),
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ]),
    );
  }
}
