import 'package:almacen_itson/core/errores/error_negocio.dart';
import 'package:almacen_itson/features/autenticacion/datos/almacen_sesion.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion.dart';
import 'package:almacen_itson/features/autenticacion/datos/sesion_repositorio.dart';
import 'package:almacen_itson/features/autenticacion/presentacion/sesion_controlador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RepositorioSesionFalso implements SesionRepositorio {
  RepositorioSesionFalso({this.sesion, this.error});

  Sesion? sesion;
  Object? error;
  int renovaciones = 0;

  @override
  Future<Sesion> iniciarSesion({
    required String usuario,
    required String contrasena,
  }) async {
    if (error != null) throw error!;
    return sesion!;
  }

  @override
  Future<Sesion> renovar(String refreshToken) async {
    renovaciones++;
    if (error != null) throw error!;
    return sesion!;
  }
}

Sesion crearSesion({required Duration expiraEn}) => Sesion(
      accessToken: 'token-acceso',
      refreshToken: 'token-renovacion',
      expiraEn: DateTime.now().add(expiraEn),
      usuario: const UsuarioSesion(
        id: 'u1',
        nombre: 'Almacén Náinari (demo)',
        email: 'almacen.nainari@itson.mx',
        rol: 'ALMACENISTA',
        campusId: 1,
        campus: 'Náinari',
      ),
    );

ProviderContainer crearContenedor(AlmacenSesion almacen, SesionRepositorio repositorio) {
  final contenedor = ProviderContainer(
    overrides: [
      proveedorAlmacenSesion.overrideWithValue(almacen),
      proveedorSesionRepositorio.overrideWithValue(repositorio),
    ],
  );
  addTearDown(contenedor.dispose);
  return contenedor;
}

void main() {
  group('ControladorSesion', () {
    test('restaura una sesión vigente guardada', () async {
      final guardada = crearSesion(expiraEn: const Duration(hours: 1));
      final contenedor = crearContenedor(AlmacenSesionMemoria(guardada), RepositorioSesionFalso());

      final sesion = await contenedor.read(controladorSesionProvider.future);

      expect(sesion, same(guardada));
    });

    test('inicia sesión, publica el estado y guarda los tokens', () async {
      final nueva = crearSesion(expiraEn: const Duration(hours: 1));
      final almacen = AlmacenSesionMemoria();
      final repositorio = RepositorioSesionFalso(sesion: nueva);
      final contenedor = crearContenedor(almacen, repositorio);
      await contenedor.read(controladorSesionProvider.future);

      final entro = await contenedor.read(controladorSesionProvider.notifier).iniciarSesion(
            usuario: 'almacen.nainari@itson.mx',
            contrasena: 'demo1234',
          );

      expect(entro, isTrue);
      expect(contenedor.read(controladorSesionProvider).value, same(nueva));
      expect(await almacen.leer(), same(nueva));
    });

    test('si las credenciales fallan, deja el error y no guarda nada', () async {
      final almacen = AlmacenSesionMemoria();
      final repositorio = RepositorioSesionFalso(
        error: const ErrorNegocio(
          'CREDENCIALES_INVALIDAS',
          'El usuario o la contraseña no son correctos.',
          estadoHttp: 401,
        ),
      );
      final contenedor = crearContenedor(almacen, repositorio);
      await contenedor.read(controladorSesionProvider.future);

      final entro = await contenedor.read(controladorSesionProvider.notifier).iniciarSesion(
            usuario: 'almacen.nainari@itson.mx',
            contrasena: 'mala',
          );

      expect(entro, isFalse);
      expect(
        contenedor.read(controladorSesionProvider).error,
        isA<ErrorNegocio>().having((e) => e.codigo, 'codigo', 'CREDENCIALES_INVALIDAS'),
      );
      expect(await almacen.leer(), isNull);
    });

    test('renueva automáticamente una sesión vencida al arrancar', () async {
      final vencida = crearSesion(expiraEn: const Duration(minutes: -5));
      final renovada = crearSesion(expiraEn: const Duration(hours: 1));
      final almacen = AlmacenSesionMemoria(vencida);
      final repositorio = RepositorioSesionFalso(sesion: renovada);
      final contenedor = crearContenedor(almacen, repositorio);

      final sesion = await contenedor.read(controladorSesionProvider.future);

      expect(sesion, same(renovada));
      expect(repositorio.renovaciones, 1);
      expect(await almacen.leer(), same(renovada));
    });

    test('si no se puede renovar, borra la sesión y pide login', () async {
      final almacen = AlmacenSesionMemoria(crearSesion(expiraEn: const Duration(minutes: -5)));
      final repositorio = RepositorioSesionFalso(
        error: const ErrorNegocio('SESION_VENCIDA', 'La sesión expiró.', estadoHttp: 401),
      );
      final contenedor = crearContenedor(almacen, repositorio);

      final sesion = await contenedor.read(controladorSesionProvider.future);

      expect(sesion, isNull);
      expect(repositorio.renovaciones, 1);
      expect(await almacen.leer(), isNull);
    });

    test('cerrar sesión borra los tokens y regresa a sin sesión', () async {
      final almacen = AlmacenSesionMemoria(crearSesion(expiraEn: const Duration(hours: 1)));
      final contenedor = crearContenedor(almacen, RepositorioSesionFalso());
      await contenedor.read(controladorSesionProvider.future);

      await contenedor.read(controladorSesionProvider.notifier).cerrarSesion();

      expect(contenedor.read(controladorSesionProvider).value, isNull);
      expect(await almacen.leer(), isNull);
    });
  });
}
