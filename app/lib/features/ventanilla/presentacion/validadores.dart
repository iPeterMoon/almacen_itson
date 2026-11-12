/// Validación de cantidad (Escenario 7). Solo mejora la experiencia: el servidor vuelve a validar.
String? validarCantidad(String? valor) {
  final texto = (valor ?? '').trim().replaceAll(',', '.');
  if (texto.isEmpty) return 'La cantidad debe ser un número mayor a cero.';
  final n = double.tryParse(texto);
  if (n == null) return 'La cantidad debe ser un número mayor a cero.';
  if (n <= 0) return 'La cantidad debe ser mayor a cero.';
  return null;
}
