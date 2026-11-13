import 'package:almacen_itson/app.dart';
import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/autenticacion/datos/almacen_sesion.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion_repositorio.dart';
import 'package:almacen_itson/features/autenticacion/presentacion/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sesion_controlador_test.dart' show RepositorioSesionFalso, crearSesion;

Widget _login(RepositorioSesionFalso repositorio) => ProviderScope(
      overrides: [
        proveedorAlmacenSesion.overrideWithValue(AlmacenSesionMemoria()),
        proveedorSesionRepositorio.overrideWithValue(repositorio),
      ],
      child: const MaterialApp(home: LoginPage()),
    );

Widget _app(RepositorioSesionFalso repositorio) => ProviderScope(
      overrides: [
        proveedorAlmacenSesion.overrideWithValue(AlmacenSesionMemoria()),
        proveedorSesionRepositorio.overrideWithValue(repositorio),
      ],
      child: const App(),
    );

Finder _campoUsuario() => find.byType(TextFormField).at(0);
Finder _campoContrasena() => find.byType(TextFormField).at(1);

Future<void> _iniciarSesion(WidgetTester tester) async {
  await tester.enterText(_campoUsuario(), 'almacen.nainari@itson.mx');
  await tester.enterText(_campoContrasena(), 'demo1234');
  await tester.ensureVisible(find.text('Iniciar sesión'));
  await tester.tap(find.text('Iniciar sesión'));
  await tester.pumpAndSettle();
}

void main() {
  group('LoginPage', () {
    testWidgets('muestra el diseño del inicio de sesión', (tester) async {
      await tester.pumpWidget(_login(RepositorioSesionFalso()));
      await tester.pumpAndSettle();

      expect(find.text('Sistema de Gestión de Almacenes'), findsOneWidget);
      expect(find.text('Inicio de sesión'), findsOneWidget);
      expect(find.text('Ingresa tus credenciales proporcionadas para acceder.'), findsOneWidget);
      expect(find.text('Usuario'), findsOneWidget);
      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(
        find.text('¿Olvidaste tu contraseña? Contacta al administrador del sistema.'),
        findsOneWidget,
      );
    });

    testWidgets('valida que el usuario y la contraseña no estén vacíos', (tester) async {
      await tester.pumpWidget(_login(RepositorioSesionFalso()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu usuario.'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    });

    testWidgets('exige un correo institucional como usuario', (tester) async {
      await tester.pumpWidget(_login(RepositorioSesionFalso()));
      await tester.pumpAndSettle();

      await tester.enterText(_campoUsuario(), 'almacen');
      await tester.enterText(_campoContrasena(), 'demo1234');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa tu correo institucional.'), findsOneWidget);
    });

    testWidgets('permite mostrar y ocultar la contraseña', (tester) async {
      await tester.pumpWidget(_login(RepositorioSesionFalso()));
      await tester.pumpAndSettle();

      bool oculta() => tester.widget<TextField>(find.byType(TextField).at(1)).obscureText;

      expect(oculta(), isTrue);
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();
      expect(oculta(), isFalse);
      await tester.tap(find.byTooltip('Ocultar contraseña'));
      await tester.pump();
      expect(oculta(), isTrue);
    });

    testWidgets('tras iniciar sesión navega a la pantalla principal', (tester) async {
      final repositorio = RepositorioSesionFalso(
        sesion: crearSesion(expiraEn: const Duration(hours: 1)),
      );
      await tester.pumpWidget(_app(repositorio));
      await tester.pumpAndSettle();

      expect(find.text('Inicio de sesión'), findsOneWidget);

      await _iniciarSesion(tester);

      expect(find.text('Ventanilla de entregas'), findsOneWidget);
      expect(find.text('+ Nueva entrega'), findsOneWidget);
      expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('permite cerrar sesión y regresa al login', (tester) async {
      final repositorio = RepositorioSesionFalso(
        sesion: crearSesion(expiraEn: const Duration(hours: 1)),
      );
      await tester.pumpWidget(_app(repositorio));
      await tester.pumpAndSettle();
      await _iniciarSesion(tester);

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Inicio de sesión'), findsOneWidget);
    });

    testWidgets('muestra el error del servidor cuando las credenciales fallan', (tester) async {
      const error = ErrorNegocio(
        'CREDENCIALES_INVALIDAS',
        'El usuario o la contraseña no son correctos.',
        estadoHttp: 401,
      );
      final repositorio = RepositorioSesionFalso(error: error);
      await tester.pumpWidget(_login(repositorio));
      await tester.pumpAndSettle();

      await tester.enterText(_campoUsuario(), 'almacen.nainari@itson.mx');
      await tester.enterText(_campoContrasena(), 'mala');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.text(error.mensaje), findsOneWidget);
      expect(find.text('Inicio de sesión'), findsOneWidget);
    });
  });
}
