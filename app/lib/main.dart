import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'arranque.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La ventanilla se usa en tableta en vertical (1200 x 1920): se bloquea la orientación.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(ProviderScope(
    overrides: proveedoresSegunEntorno(),
    retry: reintentoProveedores,
    child: const App(),
  ));
}
