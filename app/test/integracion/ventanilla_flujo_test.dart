// Pruebas de integración de la HU 6 en la app (AI-60).
//
// Se arranca la App completa (router, sesión, pantallas, controlador y repositorios
// reales) con las mismas sobreescrituras que usa main.dart (proveedoresSegunEntorno,
// que conecta la ventanilla a la API). Lo único simulado es la red: Dio usa
// ServidorApiFalso, que responde con el contrato del servidor NestJS. Así se prueba
// el recorrido del almacenista de punta a punta: solicitante → materiales →
// revisión → firmas → folio, y lo que pasa cuando el servidor rechaza algo.
import 'package:almacen_itson/app.dart';
import 'package:almacen_itson/arranque.dart';
import 'package:almacen_itson/core/config/configuracion_api.dart';
import 'package:almacen_itson/core/red/cliente_api.dart';
import 'package:almacen_itson/features/autenticacion/datos/almacen_sesion.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signature/signature.dart';

import '../apoyo/servidor_api_falso.dart';

const _url = 'http://api.prueba/api/v1';
const _token = 'token-de-prueba';
const _supervisorId = '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f';

final _sesion = Sesion(
  accessToken: _token,
  refreshToken: 'refresh',
  expiraEn: DateTime.now().add(const Duration(hours: 1)),
  usuario: const UsuarioSesion(
    id: 'u-alm',
    nombre: 'Alicia García',
    email: 'alicia@itson.edu.mx',
    rol: 'ALMACENISTA',
    campusId: 2,
    campus: 'Centro',
  ),
);

const _trabajador = {
  'id': 15,
  'nombre': 'Miguel Ángel Ruiz',
  'tipo': 'ITSON',
  'compania': null,
  'dependencia': 'SERVICIOS_GENERALES',
  'puesto': 'Intendencia',
  'campusId': 2,
  'zonas': [
    {'id': 3, 'nombre': 'Baños edificio 2', 'edificio': 'Edificio 2', 'piso': '1'},
  ],
};

const _jabon = {
  'id': 12,
  'codigo': 'JAB-001',
  'nombreEstandar': 'Jabón líquido',
  'alias': 'Jabón de manos',
  'categoria': 'Limpieza',
  'unidad': 'Litro',
  'tipo': 'SERVICIOS_GENERALES',
  'masComunes': true,
  'existencia': 10,
  'ultimaEntrada': null,
  'ultimaSalida': null,
  'ubicaciones': [
    {
      'campusId': 2,
      'almacenId': 5,
      'almacen': 'Almacén 1',
      'ubicacionId': 1,
      'ubicacion': 'E1F1',
      'cantidad': 10,
    },
  ],
};

Map<String, dynamic> _validacion({
  bool stockSuficiente = true,
  bool excedePeriodicidad = false,
  double disponible = 10,
  double? cantidadSugerida,
}) =>
    {
      'disponible': disponible,
      'ultimaEntrega': excedePeriodicidad ? '2026-11-11T18:00:00.000Z' : null,
      'proximaEntrega': excedePeriodicidad ? '2026-11-14T18:00:00.000Z' : null,
      'diasFaltantes': excedePeriodicidad ? 2 : null,
      'limiteCantidad': 2,
      'limiteCadaDias': 3,
      'entregadoPeriodo': excedePeriodicidad ? 2 : 0,
      'stockSuficiente': stockSuficiente,
      'cantidadSugerida': cantidadSugerida,
      'excedePeriodicidad': excedePeriodicidad,
      'excedeLimite': false,
    };

/// Servidor con el catálogo que necesita la ventanilla y una entrega que sale bien.
/// Cada prueba cambia solo las rutas que le interesan.
ServidorApiFalso _servidorBase() {
  final s = ServidorApiFalso();
  s.en('GET /trabajadores', (_) => const RespuestaApi.ok({
        'datos': [_trabajador],
        'total': 1,
        'pagina': 1,
        'limite': 8,
      }));
  s.en('GET /usuarios/supervisores', (_) => const RespuestaApi.ok([
        {'id': _supervisorId, 'nombre': 'Leonel Lares', 'rol': 'SUPERVISOR'},
      ]));
  s.en('GET /catalogo/categorias', (_) => const RespuestaApi.ok([
        {'id': 1, 'nombre': 'Limpieza'},
      ]));
  s.en('GET /catalogo/almacenes', (_) => const RespuestaApi.ok([
        {'id': 5, 'nombre': 'Almacén 1', 'campusId': 2, 'campus': 'Centro'},
      ]));
  s.en('GET /catalogo/productos', (_) => const RespuestaApi.ok({
        'datos': [_jabon],
        'total': 1,
        'pagina': 1,
        'limite': 8,
      }));
  s.en('POST /boletas/validar-material', (_) => RespuestaApi.ok(_validacion()));
  s.en('POST /boletas/firmas', (p) {
    final tipo = (p.cuerpo['tipo'] as String).toLowerCase();
    return RespuestaApi.creado({'ruta': '2/firma-$tipo.png'});
  });
  s.en('POST /boletas', (_) => const RespuestaApi.creado({
        'boletaId': 7,
        'folio': 'BOL-2026-000007',
        'estado': 'ENTREGADA',
        'alertas': [],
        'resumen': null,
      }));
  // 18:00 UTC = 11:00 a.m. en Hermosillo.
  s.en('GET /boletas/7', (_) => const RespuestaApi.ok({'id': 7, 'entregadoEn': '2026-11-12T18:00:00.000Z'}));
  return s;
}

/// Arranca la App con sesión iniciada y la red simulada por [servidor].
Future<void> _abrirApp(WidgetTester tester, ServidorApiFalso servidor) async {
  tester.view.physicalSize = const Size(1200, 1920); // tableta en vertical
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    retry: reintentoProveedores,
    overrides: [
      ...proveedoresSegunEntorno(urlApi: _url),
      proveedorUrlApi.overrideWithValue(_url),
      proveedorAlmacenSesion.overrideWithValue(AlmacenSesionMemoria(_sesion)),
      proveedorClienteApi.overrideWith((ref) => crearClienteApi(
            urlBase: _url,
            obtenerToken: ref.watch(proveedorObtenerToken),
            alPerderSesion: () => ref.read(proveedorAlPerderSesion)(),
            adaptador: servidor,
          )),
    ],
    child: const App(),
  ));
  await tester.pumpAndSettle();
}

Finder _boton(String texto) => find.widgetWithText(FilledButton, texto);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Escribe en un campo de búsqueda y espera la pausa de 300 ms antes de consultar.
Future<void> _buscar(WidgetTester tester, String pista, String texto) async {
  await tester.enterText(find.widgetWithText(TextField, pista), texto);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _elegirSolicitanteRegistrado(WidgetTester tester) async {
  await _tocar(tester, _boton('+ Nueva entrega'));
  await _buscar(tester, 'Buscar por nombre del solicitante', 'miguel');
  await _tocar(tester, find.text('Miguel Ángel Ruiz'));
}

/// Toca sin esperar a que todo se asiente: mientras el diálogo de autorización está
/// abierto, "Agregar Material" sigue con su indicador de carga girando debajo.
Future<void> _tocarConCarga(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Abre "Agregar Material" del jabón, captura la cantidad y toca Agregar.
Future<void> _agregarJabon(WidgetTester tester, String cantidad) async {
  await _tocar(tester, find.text('Jabón de manos'));
  await tester.enterText(find.byType(TextFormField), cantidad);
  await _tocarConCarga(tester, _boton('Agregar'));
  // Si no se abrió el diálogo de autorización, el indicador ya se detuvo.
  if (find.text('Límite de material alcanzado (Requiere autorización)').evaluate().isEmpty) {
    await tester.pumpAndSettle();
  }
}

/// Dibuja un trazo en cada lienzo de firma. El PNG se genera de forma asíncrona
/// fuera del reloj simulado, por eso se da tiempo real con runAsync.
Future<void> _firmar(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    final lienzo = find.byType(Signature).at(i);
    await tester.ensureVisible(lienzo);
    await tester.pumpAndSettle();
    await tester.drag(lienzo, const Offset(120, 30));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }
}

/// Paso 2 → 3 → 4: revisa que todo llegue marcado como entregado, firma y confirma.
Future<void> _revisarFirmarYConfirmar(WidgetTester tester) async {
  await _tocar(tester, _boton('Siguiente'));
  // Cada partida entra marcada como entregada; el almacenista solo desmarca lo que no sale.
  expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).every((c) => c.value == true), isTrue);
  await _tocar(tester, _boton('Siguiente'));
  await _firmar(tester);
  await _tocar(tester, _boton('Confirmar Entrega'));
}

void main() {
  testWidgets('entrega completa a un trabajador registrado: de la búsqueda al folio (E1)', (tester) async {
    final servidor = _servidorBase();
    await _abrirApp(tester, servidor);

    // Con sesión guardada el router entra directo a la pantalla principal.
    expect(find.text('Ventanilla de entregas'), findsOneWidget);

    await _elegirSolicitanteRegistrado(tester);
    expect(find.text('Información del trabajador seleccionado'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'No. Solicitud (Opcional)'), 'OT-9981');
    await _tocar(tester, _boton('Siguiente'));

    // Paso 2: abre con "Más comunes".
    expect(servidor.a('GET /catalogo/productos').last.consulta['soloMasComunes'], 'true');
    await _agregarJabon(tester, '2');
    expect(find.text('Agregar Material'), findsNothing, reason: 'el diálogo se cierra al agregar');

    // La validación lleva al trabajador y su única zona.
    expect(servidor.a('POST /boletas/validar-material').single.cuerpo,
        {'productoId': 12, 'cantidad': 2.0, 'trabajadorId': 15, 'zonaId': 3});

    await _revisarFirmarYConfirmar(tester);

    // Se suben las dos firmas y se crea la boleta con sus rutas.
    expect(servidor.a('POST /boletas/firmas').map((p) => p.cuerpo['tipo']).toSet(), {'RECIBE', 'ENTREGA'});
    expect(servidor.a('POST /boletas/firmas').first.cuerpo['imagenBase64'],
        startsWith('data:image/png;base64,'));
    expect(servidor.a('POST /boletas').single.cuerpo, {
      'materiales': [
        {'productoId': 12, 'cantidad': 2.0},
      ],
      'trabajadorId': 15,
      'zonaId': 3,
      'numeroSolicitud': 'OT-9981',
      'firmaRecibe': '2/firma-recibe.png',
      'firmaEntrega': '2/firma-entrega.png',
    });

    // Resumen con el folio que generó el servidor y la hora de Hermosillo.
    expect(find.text('Folio BOL-2026-000007'), findsOneWidget);
    expect(find.text('Recibida por Miguel Ángel Ruiz'), findsOneWidget);
    expect(find.textContaining('11:00 a.m. 12/11/2026'), findsOneWidget);
    expect(find.textContaining('Alicia García'), findsWidgets);
    expect(find.text('2 Litro'), findsOneWidget);

    // Todas las peticiones llevan el token de la sesión y ninguna ruta quedó sin simular.
    expect(servidor.peticiones.map((p) => p.autorizacion).toSet(), {'Bearer $_token'});
    expect(servidor.noSimuladas, isEmpty);

    await _tocar(tester, find.text('Volver a ventanilla'));
    expect(find.text('+ Nueva entrega'), findsOneWidget);
  });

  testWidgets('material fuera de periodicidad: pide motivo y autorización y la boleta queda pendiente (E8)',
      (tester) async {
    final servidor = _servidorBase()
      ..en('POST /boletas/validar-material', (_) => RespuestaApi.ok(_validacion(excedePeriodicidad: true)))
      ..en('POST /boletas', (_) => const RespuestaApi.creado({
            'boletaId': 9,
            'folio': 'BOL-2026-000009',
            'estado': 'PENDIENTE_AUTORIZACION',
            'alertas': [],
            'resumen': null,
          }));
    await _abrirApp(tester, servidor);
    await _elegirSolicitanteRegistrado(tester);
    await _tocar(tester, _boton('Siguiente'));

    await _agregarJabon(tester, '2');

    // El servidor dijo que rompe la periodicidad: se muestra la regla y no se agrega sin motivo.
    expect(find.text('Límite de material alcanzado (Requiere autorización)'), findsOneWidget);
    expect(find.text('Periodicidad no cumplida'), findsOneWidget);
    expect(find.text('2 Litro cada 3 días'), findsOneWidget);
    expect(tester.widget<FilledButton>(_boton('Autorizar')).onPressed, isNull);
    await _tocarConCarga(tester, find.text('Evento'));
    await _tocarConCarga(tester, _boton('Autorizar'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar Material'), findsNothing);

    await _tocar(tester, _boton('Siguiente'));
    expect(find.text('Entrega autorizada'), findsOneWidget);
    await _tocar(tester, _boton('Siguiente'));
    // Quien autoriza la excepción aparece en la pantalla de firmas.
    expect(find.text('Leonel Lares'), findsOneWidget);
    await _firmar(tester);
    await _tocar(tester, _boton('Confirmar Entrega'));

    final boleta = servidor.a('POST /boletas').single.cuerpo;
    expect(boleta['materiales'], [
      {'productoId': 12, 'cantidad': 2.0, 'motivoExcepcion': 'Evento'},
    ]);
    expect(boleta['supervisorId'], _supervisorId);

    // Pendiente: el resumen lo advierte y no se pide la fecha de entrega (aún no hay).
    expect(find.text('Folio BOL-2026-000009'), findsOneWidget);
    expect(find.textContaining('No la registres otra vez'), findsOneWidget);
    expect(servidor.a('GET /boletas/9'), isEmpty);
    expect(servidor.noSimuladas, isEmpty);
  });

  testWidgets('sin existencia suficiente al agregar: avisa cuánto hay y no agrega el material (E6)',
      (tester) async {
    final servidor = _servidorBase()
      ..en('POST /boletas/validar-material',
          (_) => RespuestaApi.ok(_validacion(stockSuficiente: false, disponible: 4, cantidadSugerida: 4)));
    await _abrirApp(tester, servidor);
    await _elegirSolicitanteRegistrado(tester);
    await _tocar(tester, _boton('Siguiente'));

    await _agregarJabon(tester, '6');

    expect(find.text('Agregar Material'), findsOneWidget, reason: 'el diálogo sigue abierto');
    expect(find.text('No hay existencia suficiente de Jabón líquido: solicitaste 6 Litro y hay 4 Litro.'),
        findsOneWidget);
    await _tocar(tester, find.widgetWithText(OutlinedButton, 'Cancelar').last);
    expect(tester.widget<FilledButton>(_boton('Siguiente')).onPressed, isNull,
        reason: 'sin partidas no se puede avanzar');
  });

  testWidgets('si el stock se acaba al confirmar ofrece ajustar a lo disponible y reintenta (E6)',
      (tester) async {
    var intentos = 0;
    final servidor = _servidorBase()
      ..en('POST /boletas', (p) {
        intentos++;
        if (intentos == 1) {
          // Mismo cuerpo que arma ConfirmacionService en el servidor.
          return RespuestaApi.error(
            409,
            'STOCK_INSUFICIENTE',
            'Existencia insuficiente de Jabón líquido: se solicitaron 6 Litro y solo hay 4 Litro en el campus.',
            {
              'productoId': 12,
              'codigo': 'JAB-001',
              'nombre': 'Jabón líquido',
              'solicitado': 6,
              'disponible': 4,
              'unidad': 'Litro',
              'disponibleBase': 4,
              'cantidadSugerida': 4,
            },
          );
        }
        return const RespuestaApi.creado(
            {'boletaId': 7, 'folio': 'BOL-2026-000007', 'estado': 'ENTREGADA', 'alertas': [], 'resumen': null});
      });
    await _abrirApp(tester, servidor);
    await _elegirSolicitanteRegistrado(tester);
    await _tocar(tester, _boton('Siguiente'));
    await _agregarJabon(tester, '6');
    await _revisarFirmarYConfirmar(tester);

    expect(find.text('Existencia insuficiente'), findsOneWidget);
    expect(find.textContaining('el campus solo tiene 4 Litro'), findsOneWidget);
    await _tocar(tester, _boton('Ajustar a 4'));

    // Se queda en las firmas (ya capturadas) y se puede volver a confirmar.
    await _tocar(tester, _boton('Confirmar Entrega'));
    expect(servidor.a('POST /boletas').last.cuerpo['materiales'], [
      {'productoId': 12, 'cantidad': 4.0},
    ]);
    expect(find.text('Folio BOL-2026-000007'), findsOneWidget);
    expect(find.text('4 Litro'), findsOneWidget);
  });

  testWidgets('solicitante sin registro: valida solo existencia y manda nombre, unidad y quién autorizó (E2-E4)',
      (tester) async {
    final servidor = _servidorBase();
    await _abrirApp(tester, servidor);
    await _tocar(tester, _boton('+ Nueva entrega'));

    expect(tester.widget<FilledButton>(_boton('Siguiente')).onPressed, isNull);
    await _tocar(tester, find.text('Usar solicitante sin registro'));
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Rosa Valdez');
    await tester.enterText(find.widgetWithText(TextField, 'Unidad/Campus'), 'Mantenimiento externo');
    await _tocar(tester, find.text('Sin seleccionar'));
    await _tocar(tester, find.text('Leonel Lares').last);
    await _tocar(tester, _boton('Siguiente'));

    await _agregarJabon(tester, '1');
    // Sin trabajador no hay periodicidad ni límite de zona que revisar.
    expect(servidor.a('POST /boletas/validar-material').single.cuerpo, {'productoId': 12, 'cantidad': 1.0});

    await _revisarFirmarYConfirmar(tester);

    final boleta = servidor.a('POST /boletas').single.cuerpo;
    expect(boleta, containsPair('solicitanteNombre', 'Rosa Valdez'));
    expect(boleta, containsPair('solicitanteUnidad', 'Mantenimiento externo'));
    expect(boleta, containsPair('autorizoNombre', 'Leonel Lares'));
    expect(boleta.keys, isNot(contains('trabajadorId')));
    expect(boleta.keys, isNot(contains('numeroSolicitud')), reason: 'el número de solicitud es opcional');
    expect(find.text('Recibida por Rosa Valdez'), findsOneWidget);
  });

  testWidgets('un error del servidor al confirmar se muestra y permite reintentar sin perder la boleta',
      (tester) async {
    final servidor = _servidorBase()
      ..en('POST /boletas',
          (_) => RespuestaApi.error(500, 'ERROR_INTERNO', 'Ocurrió un error inesperado. Intenta de nuevo.'));
    await _abrirApp(tester, servidor);
    await _elegirSolicitanteRegistrado(tester);
    await _tocar(tester, _boton('Siguiente'));
    await _agregarJabon(tester, '2');
    await _revisarFirmarYConfirmar(tester);

    expect(find.text('Ocurrió un error inesperado. Intenta de nuevo.'), findsOneWidget);
    expect(find.textContaining('Folio'), findsNothing);
    expect(tester.widget<FilledButton>(_boton('Confirmar Entrega')).onPressed, isNotNull);
  });

  testWidgets('si el servidor rechaza la sesión (401) vuelve al inicio de sesión', (tester) async {
    final servidor = _servidorBase()
      ..en('GET /trabajadores',
          (_) => RespuestaApi.error(401, 'NO_AUTENTICADO', 'La sesión expiró. Vuelve a iniciar sesión.'));
    await _abrirApp(tester, servidor);
    await _tocar(tester, _boton('+ Nueva entrega'));

    expect(find.text('Iniciar sesión'), findsWidgets);
    expect(find.text('Ventanilla de entregas'), findsNothing);
  });
}
