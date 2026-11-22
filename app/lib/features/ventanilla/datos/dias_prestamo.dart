// Reglas de interfaz de los días de préstamo de una herramienta (HU8).
// El servidor valida que sean enteros de 1 a DIAS_PRESTAMO_MAX (30, en
// servidor/src/comun/dto/limites.ts). El máximo de la app debe ser el mismo: con más
// días la boleta avanzaría aquí y POST /boletas la rechazaría con 400.

/// Días con los que se agrega una herramienta a la boleta.
const diasPrestamoPredeterminado = 1;
const diasPrestamoMinimo = 1;
const diasPrestamoMaximo = 30;

const mensajeDiasInvalidos = 'El tiempo de préstamo debe ser mayor a cero días';

/// Convierte lo escrito en el campo de días. Vacío o sin número es 0 (inválido, y la
/// boleta no avanza); más de [diasPrestamoMaximo] se queda en el máximo.
int diasDeTexto(String texto) {
  final dias = int.tryParse(texto.trim()) ?? 0;
  if (dias < 0) return 0;
  return dias > diasPrestamoMaximo ? diasPrestamoMaximo : dias;
}

bool diasPrestamoValidos(int dias) => dias >= diasPrestamoMinimo;

// Hermosillo no cambia de horario (Sonora no usa horario de verano): siempre UTC-7.
// Se resta el desfase fijo en lugar de depender de la zona horaria del dispositivo.
const _desfaseHermosillo = Duration(hours: -7);

/// La hora de Hermosillo del instante dado. Sus campos (año, mes, día, hora) son los
/// que marcaría un reloj en Hermosillo; el objeto va marcado como UTC solo por conveniencia.
DateTime aHoraDeHermosillo(DateTime instante) => instante.toUtc().add(_desfaseHermosillo);

/// Fecha prevista de devolución: el día de hoy en Hermosillo más [dias] días naturales.
/// Devuelve solo la fecha (sin hora).
DateTime fechaPrevistaDevolucion(DateTime ahora, int dias) {
  final hoy = aHoraDeHermosillo(ahora);
  // DateTime.utc acomoda solo los días de más (fin de mes, fin de año, bisiestos).
  return DateTime.utc(hoy.year, hoy.month, hoy.day + dias);
}

/// DD/MM/AAAA.
String formatearFecha(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year.toString().padLeft(4, '0')}';
}

/// La fecha prevista de devolución ya formateada, lista para mostrar.
String fechaPrevistaTexto(DateTime ahora, int dias) =>
    formatearFecha(fechaPrevistaDevolucion(ahora, dias));
