import 'package:almacen_itson/features/ventanilla/presentacion/entrega_controlador.dart';
import 'package:almacen_itson/features/ventanilla/presentacion/widgets/paso_materiales.dart';
import 'package:flutter_test/flutter_test.dart';

// Qué mensaje ve el usuario cuando la tabla de materiales llega vacía (AI-30 y AI-62).
void main() {
  FiltroMateriales filtro({String consulta = '', bool soloComunes = true, String? categoria}) =>
      FiltroMateriales(consulta: consulta, soloComunes: soloComunes, categoria: categoria);

  test('con 1 carácter pide escribir al menos 2, con cualquier filtro', () {
    expect(mensajeListaVacia(filtro(consulta: 'a')), mensajeEscribeParaBuscar);
    expect(mensajeListaVacia(filtro(consulta: ' p ', soloComunes: false)), mensajeEscribeParaBuscar);
  });

  test('con texto y "Más comunes" sugiere el filtro Todos', () {
    expect(
      mensajeListaVacia(filtro(consulta: 'desengr')),
      'No hay materiales disponibles con ese nombre. Prueba con el filtro Todos.',
    );
  });

  test('con texto y "Todos" no sugiere nada', () {
    expect(
      mensajeListaVacia(filtro(consulta: 'CD-500', soloComunes: false)),
      'No hay materiales disponibles con ese nombre',
    );
  });

  test('sin texto y con "Más comunes" sugiere el filtro Todos', () {
    expect(mensajeListaVacia(filtro()), mensajeSinMasComunes);
  });

  test('sin texto, con "Todos" y filtros, indica que no hay con esos filtros', () {
    expect(
      mensajeListaVacia(filtro(soloComunes: false, categoria: 'Papel')),
      mensajeSinMaterialesFiltros,
    );
  });
}
