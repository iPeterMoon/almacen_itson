# Almacenes ITSON — app móvil

App Flutter (Android) del sistema Almacenes ITSON. Solo habla con la API REST del servidor
NestJS (`../servidor`); nunca con Supabase directamente ni guarda claves de Supabase.

## Cómo ejecutarla

```bash
cd app
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1   # emulador Android -> servidor local
flutter analyze
flutter test
```

> Por ahora la app solo abre una pantalla en blanco: es la estructura base.

## Paquetes acordados

`flutter_riverpod` (estado), `go_router` (navegación), `dio` (HTTP),
`flutter_secure_storage` (tokens de sesión) y `signature` (captura de firmas).

## Estructura (por funcionalidad)

```
lib/
  main.dart            arranque de la app (ProviderScope)
  app.dart             raíz: MaterialApp; aquí irán tema y rutas
  core/                lo compartido por todas las funcionalidades
    config/            URL del servidor (--dart-define=API_URL)
    tema/              colores, tipografía y espaciados del Figma
    red/               cliente dio con token y renovación
    errores/           ErrorNegocio a partir de { codigo, mensaje }
    widgets/           botones, campos y tarjetas reutilizables
  features/            una carpeta por funcionalidad
    autenticacion/        inicio de sesión, perfil, rol y campus
    catalogo_inventario/  HU1-5
    ventanilla/           HU6
    prestamos/            HU7-10
    alertas/              notificaciones
    reportes/             etapa futura
      (cada una con)
      datos/           repositorios que llaman a la API y modelos
      presentacion/    pantallas, widgets y controladores
test/                  pruebas
```

Cada carpeta tiene un `README.md` de una línea que explica su propósito (también hace que Git
conserve las carpetas vacías).
