import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores/error_negocio.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import 'sesion_controlador.dart';

/// Inicio de sesión con correo institucional (HU de autenticación).
/// Ruta: /login. Al entrar, el router redirige a la pantalla principal.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formulario = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  final _focoContrasena = FocusNode();

  bool _verContrasena = false;
  bool _enviando = false;

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    _focoContrasena.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (_enviando) return;
    if (!(_formulario.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _enviando = true);

    await ref.read(controladorSesionProvider.notifier).iniciarSesion(
          usuario: _usuario.text.trim(),
          contrasena: _contrasena.text,
        );

    if (mounted) setState(() => _enviando = false);
  }

  String? _validarUsuario(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return 'Ingresa tu usuario.';
    if (!texto.contains('@') || !texto.contains('.')) {
      return 'Ingresa tu correo institucional.';
    }
    return null;
  }

  String? _validarContrasena(String? valor) {
    if (valor == null || valor.isEmpty) return 'Ingresa tu contraseña.';
    return null;
  }

  InputDecoration _decoracion({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colores.deshabilitado),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      suffixIcon: suffixIcon,
      border: _borde(Colores.bordeCampo),
      enabledBorder: _borde(Colores.bordeCampo),
      focusedBorder: _borde(Colores.primario, ancho: 1.5),
      errorBorder: _borde(Colores.peligro),
      focusedErrorBorder: _borde(Colores.peligro, ancho: 1.5),
      errorStyle: const TextStyle(color: Colores.peligro),
    );
  }

  OutlineInputBorder _borde(Color color, {double ancho = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: ancho),
      );

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(controladorSesionProvider);
    final cargando = _enviando || estado.isLoading;
    final mensajeError = switch (estado.error) {
      ErrorNegocio error => error.mensaje,
      null => null,
      _ => ErrorNegocio.mensajeInesperado,
    };

    return Scaffold(
      backgroundColor: Colores.fondoLogin,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, caja) {
          final altoMinimo = caja.maxHeight > 56 ? caja.maxHeight - 56 : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: altoMinimo),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 644),
                  child: _TarjetaLogin(
                    formulario: _formulario,
                    usuario: _usuario,
                    contrasena: _contrasena,
                    focoContrasena: _focoContrasena,
                    verContrasena: _verContrasena,
                    cargando: cargando,
                    mensajeError: mensajeError,
                    decoracion: _decoracion,
                    validarUsuario: _validarUsuario,
                    validarContrasena: _validarContrasena,
                    alCambiarVisibilidad: () =>
                        setState(() => _verContrasena = !_verContrasena),
                    alEntrar: _entrar,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TarjetaLogin extends StatelessWidget {
  const _TarjetaLogin({
    required this.formulario,
    required this.usuario,
    required this.contrasena,
    required this.focoContrasena,
    required this.verContrasena,
    required this.cargando,
    required this.mensajeError,
    required this.decoracion,
    required this.validarUsuario,
    required this.validarContrasena,
    required this.alCambiarVisibilidad,
    required this.alEntrar,
  });

  final GlobalKey<FormState> formulario;
  final TextEditingController usuario;
  final TextEditingController contrasena;
  final FocusNode focoContrasena;
  final bool verContrasena;
  final bool cargando;
  final String? mensajeError;
  final InputDecoration Function({String? hint, Widget? suffixIcon}) decoracion;
  final String? Function(String?) validarUsuario;
  final String? Function(String?) validarContrasena;
  final VoidCallback alCambiarVisibilidad;
  final VoidCallback alEntrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colores.borde),
        boxShadow: const [
          BoxShadow(color: Color(0x12111827), blurRadius: 32, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _LogotipoItson()),
          const SizedBox(height: 28),
          const Text (
            'Sistema de Gestión de Almacenes',
            style: TextStyle(
              color: Colores.texto,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const Text(
            'Inicio de sesión',
            style: TextStyle(
              color: Colores.texto,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ingresa tus credenciales proporcionadas para acceder.',
            style: TextStyle(color: Colores.textoSuave, fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 28),
          AutofillGroup(
            child: Form(
              key: formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Etiqueta('Usuario'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: usuario,
                    enabled: !cargando,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    decoration: decoracion(hint: 'usuario@itson.mx'),
                    validator: validarUsuario,
                    onFieldSubmitted: (_) => focoContrasena.requestFocus(),
                  ),
                  const SizedBox(height: 18),
                  const _Etiqueta('Contraseña'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: contrasena,
                    focusNode: focoContrasena,
                    enabled: !cargando,
                    obscureText: !verContrasena,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: decoracion(
                      suffixIcon: IconButton(
                        tooltip: verContrasena ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        onPressed: cargando ? null : alCambiarVisibilidad,
                        color: Colores.textoSuave,
                        icon: Icon(
                          verContrasena ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: validarContrasena,
                    onFieldSubmitted: (_) => alEntrar(),
                  ),
                  if (mensajeError != null) ...[
                    const SizedBox(height: 16),
                    AvisoCaja(tipo: TipoAviso.error, mensaje: mensajeError!),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 51,
                    child: FilledButton(
                      onPressed: cargando ? null : alEntrar,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colores.primario,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colores.deshabilitado,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: cargando
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('Iniciar sesión'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text.rich(
              TextSpan(
                text: '¿Olvidaste tu contraseña? ',
                children: [
                  TextSpan(
                    text: 'Contacta al administrador del sistema.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colores.primario, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        color: Colores.textoEtiqueta,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LogotipoItson extends StatelessWidget {
  const _LogotipoItson();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_itson.png',
      height: 120,
      fit: BoxFit.contain,
      semanticLabel: 'ITSON',
    );
  }
}
