# Almacenes ITSON

Sistema de inventario, entregas en ventanilla y préstamo de herramientas de los almacenes del ITSON
(campus Náinari y Centro). Proyecto de Métodos Ágiles.

**Equipo:** Juan Pablo Olivarria, Pedro Luna, Alicia García, Norma Beltrán y Victoria Valenzuela.

## Arquitectura

```
App móvil (Flutter)  →  API REST (NestJS)  →  Base de datos (Supabase / PostgreSQL)
      app/                 servidor/                supabase/
```

- La app solo habla con la API; nunca con Supabase ni guarda claves de Supabase.
- El servidor actúa en nombre del usuario (con su token), así que los permisos por rol y campus
  los aplica la base con RLS.
- Las reglas de negocio (stock, folios, autorizaciones) viven en funciones de PostgreSQL.

## Carpetas

| Carpeta     | Qué contiene                                                        | Detalles                                  |
| ----------- | ------------------------------------------------------------------- | ----------------------------------------- |
| `app/`      | App Flutter para Android                                            | [app/README.md](app/README.md)            |
| `servidor/` | API REST en NestJS, 6 módulos de dominio, Swagger en `/docs`        | `servidor/.env.example`                   |
| `supabase/` | Migraciones (tablas, funciones, RLS, firmas) y datos de ejemplo     | `supabase/migrations/`                    |

## Empezar

1. Clona `https://github.com/iPeterMoon/almacen_itson.git` e instala las herramientas:
   **[INSTALACION.md](INSTALACION.md)**.
2. Servidor:
   ```bash
   cd servidor
   npm ci
   cp .env.example .env      # y llena SUPABASE_URL y SUPABASE_ANON_KEY
   npm run start:dev         # http://localhost:3000/api/v1/salud y /docs
   ```
3. App:
   ```bash
   cd app
   flutter pub get
   flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1
   ```

## Antes de subir cambios

```bash
cd servidor && npm run lint && npm test && npm run build
cd app && flutter analyze && flutter test
```

## Historias priorizadas

HU1 alta de producto · HU2 entradas · HU3 consulta · HU4 reingreso · HU5 ajuste ·
HU6 entrega en ventanilla · HU7 alta de activo · HU8 préstamo · HU9 devolución · HU10 seguimiento.
