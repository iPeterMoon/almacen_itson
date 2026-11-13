# Almacenes ITSON

Sistema de inventario, entregas en ventanilla y préstamo de herramientas de los almacenes del ITSON
(campus Náinari y Centro). Proyecto de Métodos Ágiles.

**Equipo:** Juan Pablo Olivarria, Pedro Luna, Alicia García, Norma Beltrán y Victoria Valenzuela.

## Arquitectura

```text
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
| `supabase/` | Migraciones (tablas, funciones, RLS, firmas), datos de ejemplo y pruebas | `supabase/migrations/`, `supabase/pruebas/` |

## API de boletas de entrega

El flujo de ventanilla y su historial se exponen en `servidor/src/modulos/ventanilla/`:

| Método | Ruta                             | Qué hace                                                        |
| ------ | -------------------------------- | --------------------------------------------------------------- |
| `POST` | `/api/v1/boletas/validar-material` | Valida existencia, periodicidad y límite de zona antes de agregar |
| `POST` | `/api/v1/boletas/firmas`           | Sube una firma al bucket privado `firmas` y devuelve su ruta     |
| `POST` | `/api/v1/boletas`                  | Crea la boleta; entrega en el acto o pide autorización           |
| `GET`  | `/api/v1/boletas`                  | Lista las boletas de los campus del usuario                      |
| `GET`  | `/api/v1/boletas/:id`              | Detalle con materiales, herramientas y autorización              |
| `POST` | `/api/v1/boletas/:id/autorizacion` | El supervisor autoriza o rechaza                                 |
| `POST` | `/api/v1/boletas/:id/entrega`      | Confirma la entrega con las dos firmas                           |
| `GET`  | `/api/v1/entregas`                 | Historial de material entregado por solicitante, insumo y zona   |

Todas requieren `Authorization: Bearer <token>`. El contrato completo, con ejemplos y roles,
está en Swagger (`/docs`).

## API de catálogo

La búsqueda de materiales para la boleta se expone en `servidor/src/modulos/catalogo-inventario/`:

| Método | Ruta                          | Qué hace                                                                 |
| ------ | ----------------------------- | ------------------------------------------------------------------------ |
| `GET`  | `/api/v1/catalogo/productos`  | Busca por código, nombre o alias (`texto`, 2 a 100 caracteres) solo productos con existencia en los campus del usuario; `limite` 8 por defecto, máximo 50 |

## Tipos de Supabase

`servidor/src/supabase/tipos-base.ts` se genera desde el esquema `public` de la base local:

```bash
npx supabase start        # requiere Docker
cd servidor
npm run gen:types
```

El archivo se versiona en Git y no se edita a mano. Regénéralo después de cada migración.

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
   flutter run                # sin API_URL usa datos simulados
   ```

## Probar la app con la API en local

Requisitos: Docker Desktop abierto, un emulador Android encendido (ver [INSTALACION.md](INSTALACION.md),
paso 3) y **Git Bash** (los comandos de abajo no funcionan en PowerShell). Abre las terminales en la raíz del repo.

```bash
npx supabase start
npx supabase db reset        # borra tu base local y carga usuario y productos de prueba
```

En `servidor/.env`: `SUPABASE_URL=http://127.0.0.1:54321` y `SUPABASE_ANON_KEY` = el valor de
`PUBLISHABLE_KEY` (empieza con `sb_publishable_`) de `npx supabase status -o env`.

```bash
cd servidor && npm run start:dev    # terminal 1
cd app && flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1 --dart-define=API_TOKEN=$(bash ../scripts/token-dev.sh)   # terminal 2
```

La primera compilación de Android puede tardar 10 minutos o más; el aviso "SDK XML version 4" no es
un error. El token vence en 1 hora; si vence, vuelve a correr `flutter run`.

## Pruebas de la base de datos

`supabase/pruebas/` prueba las funciones RPC, RLS y firmas contra un PostgreSQL 16 en Docker,
como los usuarios reales de la app (almacenista, supervisor y supervisor jefe de cada campus).
No usa la cuenta de Supabase ni `supabase start`: el archivo `00_stub_supabase.sql` imita lo
mínimo de Supabase (roles, `auth.uid()`, `storage`).

Requiere Docker Desktop abierto y Python 3. Desde la raíz del repo, en Git Bash:

```bash
bash supabase/pruebas/reiniciar.sh     # recrea la base: stub + migraciones + seed.sql
python supabase/pruebas/probar.py      # corre los escenarios de HU1 a HU10
```

La primera vez descarga la imagen `postgres:16` y crea el contenedor `almacenes-pruebas`
(publicado solo en `127.0.0.1:54329`, usuario y contraseña `postgres`, base `almacenes`).
Cada caso imprime `PASA` o `FALLA` con el error, y al final el total (`139/139 casos pasan`).
Corre `reiniciar.sh` antes de cada `probar.py`, porque las pruebas dejan datos en la base.
Para borrar el contenedor: `docker rm -f almacenes-pruebas`.

## Antes de subir cambios

```bash
cd servidor && npm run lint && npm test && npm run build
cd app && flutter analyze && flutter test
bash supabase/pruebas/reiniciar.sh && python supabase/pruebas/probar.py   # si tocaste supabase/
```

## Skills de Claude Code

En `.claude/skills/` hay tres skills que Claude Code carga solo al abrir el repo:

| Skill                         | Para qué                                                    |
| ----------------------------- | ----------------------------------------------------------- |
| `disenador-base-datos`        | Tablas, funciones, RLS y migraciones de Supabase            |
| `desarrollador-backend-nestjs`| Módulos, endpoints y pruebas del servidor                   |
| `desarrollador-flutter`       | Pantallas de la app a partir del Figma y la API             |

Úsalas escribiendo `/desarrollador-flutter` (o el nombre que toque) en Claude Code, o pídele la tarea
y él elige la skill.

## Historias priorizadas

HU1 alta de producto · HU2 entradas · HU3 consulta · HU4 reingreso · HU5 ajuste ·
HU6 entrega en ventanilla · HU7 alta de activo · HU8 préstamo · HU9 devolución · HU10 seguimiento.
