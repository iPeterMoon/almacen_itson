import 'package:flutter/services.dart';

/// Letras (con acentos y ñ) y espacios. No acepta números ni signos.
final RegExp expregSoloLetras = RegExp(r'^\p{L}+(?: \p{L}+)*$', unicode: true);

/// Quita cualquier carácter que no sea letra o espacio, incluso al pegar texto.
String soloLetras(String texto) => texto.replaceAll(RegExp(r'[^\p{L} ]', unicode: true), '');

/// Filtro para `inputFormatters`: deja escribir solo letras y espacios.
final List<TextInputFormatter> formattersSoloLetras = [
  FilteringTextInputFormatter.allow(RegExp(r'[\p{L} ]', unicode: true)),
];
