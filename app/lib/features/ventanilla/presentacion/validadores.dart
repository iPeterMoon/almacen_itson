import '../../../core/validacion/sin_emojis.dart';

/// La cantidad es un número entero de presentaciones completas (AI-67): nunca
/// 0.5 L, sino 1 "Medio litro". El campo deja escribir hasta 4 dígitos; el tope
/// real es la existencia, que valida el servidor (STOCK_INSUFICIENTE).
const digitosCantidad = 4;
const cantidadMaxima = 9999;

final _soloDigitos = RegExp(r'^\d+$');
final _soloCeros = RegExp(r'^0+$');
final _negativo =RegExp(r'^-\d+([.,]\d+)?$');

/// Validación de cantidad (Escenario 7). Solo mejora la experiencia: el servidor vuelve a validar.
String? validarCantidad(String? valor) {
  final sinEmojis = validarSinEmojis(valor);
  if (sinEmojis != null) return sinEmojis;
  final texto = (valor ?? '').trim();
  if (texto.isEmpty) return 'Escribe la cantidad.';
  if (_negativo.hasMatch(texto)) return 'La cantidad debe ser mayor a cero.';
  // Rechaza decimales (2.5, 2,5) y lo que no es un número (abc, 1e5, NaN, Infinity).
  if (!_soloDigitos.hasMatch(texto)) return 'La cantidad debe ser un número entero.';
  // Solo ceros (0, 0000, 00000000), sin importar cuántos: el problema es el valor.
  if (_soloCeros.hasMatch(texto)) return 'La cantidad debe ser mayor a cero.';
  if (texto.startsWith('0')) return 'Escribe la cantidad sin ceros a la izquierda.';
  if (texto.length > digitosCantidad) return 'La cantidad máxima es $cantidadMaxima.';
  return null;
}
