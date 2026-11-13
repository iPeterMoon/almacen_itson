import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/cliente_api.dart';
import '../datos/almacen_sesion.dart';
import '../datos/sesion.dart';
import '../datos/sesion_repositorio.dart';

// Estado global de la sesión. Mientras carga, la app puede mostrar el login;
// cuando hay sesión, el router deja pasar a las pantallas protegidas.
class ControladorSesion extends AsyncNotifier<Sesion?> {
  @override
  Future<Sesion?> build() async {
    final almacen = ref.watch(proveedorAlmacenSesion);
    final sesion = await almacen.leer();
    if (sesion == null) return null;

    if (sesion.estaVigente) return sesion;

    // La sesión guardada venció: se intenta renovar antes de pedir login.
    try {
      final renovada = await ref.read(proveedorSesionRepositorio).renovar(sesion.refreshToken);
      await almacen.guardar(renovada);
      return renovada;
    } catch (_) {
      await almacen.borrar();
      return null;
    }
  }

  Future<bool> iniciarSesion({
    required String usuario,
    required String contrasena,
  }) async {
    state = const AsyncLoading();
    final resultado = await AsyncValue.guard<Sesion?>(() async {
      final sesion = await ref.read(proveedorSesionRepositorio).iniciarSesion(
            usuario: usuario,
            contrasena: contrasena,
          );
      await ref.read(proveedorAlmacenSesion).guardar(sesion);
      return sesion;
    });
    state = resultado;
    return !resultado.hasError;
  }

  Future<void> cerrarSesion() async {
    await ref.read(proveedorAlmacenSesion).borrar();
    state = const AsyncData(null);
  }
}

final controladorSesionProvider =
    AsyncNotifierProvider<ControladorSesion, Sesion?>(ControladorSesion.new);

// Lo usa el cliente HTTP en cada petición. Si el token está por vencer, lo
// renueva antes de mandarlo; si ya no se puede renovar, devuelve null para que
// el usuario vuelva al inicio de sesión.
final proveedorTokenSesion = Provider<ObtenerToken>((ref) {
  final almacen = ref.watch(proveedorAlmacenSesion);
  final repositorio = ref.watch(proveedorSesionRepositorio);

  return () async {
    var sesion = await almacen.leer();
    if (sesion == null) return null;

    if (!sesion.estaVigente) {
      try {
        sesion = await repositorio.renovar(sesion.refreshToken);
        await almacen.guardar(sesion);
      } catch (_) {
        await almacen.borrar();
        return null;
      }
    }
    return sesion.accessToken;
  };
});
