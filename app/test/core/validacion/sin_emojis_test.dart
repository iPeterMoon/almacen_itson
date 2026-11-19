import 'package:almacen_itson/core/validacion/sin_emojis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contieneEmojis', () {
    test('detecta emoticones, banderas y secuencias compuestas', () {
      expect(contieneEmojis('Hola 😀'), isTrue);
      expect(contieneEmojis('México 🇲🇽'), isTrue);
      expect(contieneEmojis('Familia 👨‍👩‍👧‍👦'), isTrue);
      expect(contieneEmojis('Café ☕'), isTrue);
      expect(contieneEmojis('Estrella ⭐'), isTrue);
      expect(contieneEmojis('Aprobado ✅'), isTrue);
    });

    test('no confunde acentos, ñ ni signos con emojis', () {
      expect(contieneEmojis('Ángel Niño OT-9981, 2,5'), isFalse);
      expect(contieneEmojis('Jabón líquido - 16 L'), isFalse);
      expect(contieneEmojis(''), isFalse);
    });
  });

  group('quitarEmojis', () {
    test('elimina los emojis y conserva el resto del texto', () {
      expect(quitarEmojis('Rosa😀 Valdez'), 'Rosa Valdez');
      expect(quitarEmojis(' Familia 👨‍👩‍👧‍👦 '), ' Familia  ');
      expect(quitarEmojis('Ángel Niño'), 'Ángel Niño');
    });
  });

  test('validarSinEmojis devuelve error solo cuando hay emojis', () {
    expect(validarSinEmojis('demo😀1234'), 'No se permiten emojis.');
    expect(validarSinEmojis('demo1234'), isNull);
    expect(validarSinEmojis(null), isNull);
  });

  test('el filtro quita emojis al escribir y al pegar', () {
    const pegado = TextEditingValue(text: 'OT-9981😀');
    final resultado = formattersSinEmojis.fold<TextEditingValue>(
      pegado,
      (valor, formatter) => formatter.formatEditUpdate(TextEditingValue.empty, valor),
    );

    expect(resultado.text, 'OT-9981');
    expect(formattersSinEmojis, isNotEmpty);
  });
}
