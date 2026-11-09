import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almacen_itson/app.dart';

void main() {
  testWidgets('la app arranca y muestra una pantalla en blanco', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AlmacenItsonApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
