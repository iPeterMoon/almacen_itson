import 'package:flutter/services.dart';

/// Caracteres que se tratan como emoji: emoticones, pictogramas, banderas,
/// símbolos que se muestran como emoji y las piezas de las secuencias compuestas
/// (modificador de piel, selector de variación, unión ancha y tecla base).
///
/// Los acentos, la ñ y los signos usados en la app (como "-", "." o ",") no
/// pertenecen a estos rangos y por eso se conservan.
final RegExp expregEmojis = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{20E3}\u{FE0F}\u{200D}]',
  unicode: true,
);

/// Devuelve [texto] sin ningún emoji.
String quitarEmojis(String texto) => texto.replaceAll(expregEmojis, '');

/// true si [texto] contiene al menos un emoji.
bool contieneEmojis(String texto) => expregEmojis.hasMatch(texto);

/// Validador de formulario: devuelve null cuando no hay emojis.
String? validarSinEmojis(String? valor) =>
    contieneEmojis(valor ?? '') ? 'No se permiten emojis.' : null;

/// Filtro listo para `inputFormatters` de cualquier TextField/TextFormField.
/// Quita el emoji tanto al escribir como al pegar texto.
final List<TextInputFormatter> formattersSinEmojis = [
  FilteringTextInputFormatter.deny(expregEmojis),
];
