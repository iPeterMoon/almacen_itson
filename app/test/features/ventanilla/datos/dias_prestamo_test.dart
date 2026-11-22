import 'package:almacen_itson/features/ventanilla/datos/dias_prestamo.dart';
import 'package:flutter_test/flutter_test.dart';

// HU8 · Fecha prevista de devolución = hoy + días (DD/MM/AAAA, hora de Hermosillo).
// Hermosillo es UTC-7 todo el año, así que 18:00 UTC son las 11:00 en Hermosillo.
void main() {
  group('fechaPrevistaTexto', () {
    final hoy = DateTime.utc(2026, 11, 19, 18); // 19/11/2026, 11:00 en Hermosillo

    test('suma los días a hoy', () {
      expect(fechaPrevistaTexto(hoy, 1), '20/11/2026');
      expect(fechaPrevistaTexto(hoy, 3), '22/11/2026');
      expect(fechaPrevistaTexto(hoy, 10), '29/11/2026');
    });

    test('cruza fin de mes y fin de año', () {
      expect(fechaPrevistaTexto(DateTime.utc(2026, 11, 30, 18), 1), '01/12/2026');
      expect(fechaPrevistaTexto(DateTime.utc(2026, 12, 31, 18), 1), '01/01/2027');
      expect(fechaPrevistaTexto(hoy, 45), '03/01/2027');
    });

    test('respeta los años bisiestos', () {
      expect(fechaPrevistaTexto(DateTime.utc(2028, 2, 28, 18), 1), '29/02/2028');
      expect(fechaPrevistaTexto(DateTime.utc(2027, 2, 28, 18), 1), '01/03/2027');
    });

    test('con el máximo de 30 días llega al mismo día del mes siguiente', () {
      expect(fechaPrevistaTexto(hoy, diasPrestamoMaximo), '19/12/2026');
    });

    test('rellena con ceros el día y el mes', () {
      expect(fechaPrevistaTexto(DateTime.utc(2026, 1, 4, 18), 1), '05/01/2026');
    });

    test('"hoy" es el día en Hermosillo, no el de UTC', () {
      // 03:00 UTC del 20/11 todavía es 20:00 del 19/11 en Hermosillo.
      expect(fechaPrevistaTexto(DateTime.utc(2026, 11, 20, 3), 1), '20/11/2026');
      // 07:00 UTC del 20/11 es la medianoche del 20/11 en Hermosillo.
      expect(fechaPrevistaTexto(DateTime.utc(2026, 11, 20, 7), 1), '21/11/2026');
      // 06:59 UTC del 20/11 es todavía 23:59 del 19/11.
      expect(fechaPrevistaTexto(DateTime.utc(2026, 11, 20, 6, 59), 1), '20/11/2026');
    });

    test('da el mismo resultado sin importar la zona horaria del dispositivo', () {
      final utc = DateTime.utc(2026, 11, 20, 3);
      final local = DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
      expect(fechaPrevistaTexto(local, 2), fechaPrevistaTexto(utc, 2));
    });

    test('se recalcula al cambiar los días', () {
      expect(fechaPrevistaTexto(hoy, 2), isNot(fechaPrevistaTexto(hoy, 5)));
    });
  });

  group('fechaPrevistaDevolucion', () {
    test('devuelve solo la fecha, sin hora', () {
      final f = fechaPrevistaDevolucion(DateTime.utc(2026, 11, 19, 18, 45), 2);
      expect([f.year, f.month, f.day, f.hour, f.minute], [2026, 11, 21, 0, 0]);
    });
  });

  group('diasDeTexto', () {
    test('un número normal', () {
      expect(diasDeTexto('7'), 7);
      expect(diasDeTexto(' 12 '), 12);
      expect(diasDeTexto('30'), 30);
    });

    test('vacío, en 0 o sin número queda en 0 (inválido)', () {
      expect(diasDeTexto(''), 0);
      expect(diasDeTexto('   '), 0);
      expect(diasDeTexto('0'), 0);
      expect(diasDeTexto('abc'), 0);
      expect(diasDeTexto('-3'), 0);
    });

    test('más del máximo se queda en el máximo', () {
      expect(diasDeTexto('31'), 30);
      expect(diasDeTexto('999'), 30);
    });
  });

  test('límites y valor por defecto', () {
    expect(diasPrestamoPredeterminado, 1);
    expect(diasPrestamoMinimo, 1);
    expect(diasPrestamoMaximo, 30, reason: 'igual que DIAS_PRESTAMO_MAX del servidor');
    expect(diasPrestamoValidos(0), isFalse);
    expect(diasPrestamoValidos(1), isTrue);
    expect(diasPrestamoValidos(30), isTrue);
    expect(mensajeDiasInvalidos, 'El tiempo de préstamo debe ser mayor a cero días');
  });
}
