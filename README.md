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

## API de listas para la boleta

Las listas de selección del flujo de ventanilla. Todas son de solo lectura y la base (RLS) las
limita a los campus del usuario. Las búsquedas aceptan `texto` (2 a 100 caracteres: letras,
números, espacios y `. - / # '`), `pagina` y `limite` (8 por defecto, máximo 50).

| Método | Ruta                          | Qué hace                                                              |
| ------ | ----------------------------- | --------------------------------------------------------------------- |
| `GET`  | `/api/v1/trabajadores`        | Solicitantes registrados con sus zonas (ventanilla)                    |
| `GET`  | `/api/v1/usuarios/supervisores` | Supervisores que pueden autorizar una excepción (usuarios y roles)    |
| `GET`  | `/api/v1/activos`             | Herramientas por código, nombre o serie; `estado=DISPONIBLE` para prestar (préstamos) |

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
   cp .env.example .env      # y llena SUPABASE_URL y SUPABASE_ANON_KEY (ver "Elegir la base de datos")
   npm run start:dev         # http://localhost:3000/api/v1/salud y /docs
   ```

3. App:

   ```bash
   cd app
   flutter pub get
   flutter run                # sin API_URL usa datos simulados
   ```

## Elegir la base de datos

El servidor puede usar una de dos bases. Solo cambia `servidor/.env`; la app y el servidor
funcionan igual con cualquiera.

| Opción | Cuándo conviene | Requisitos |
| ------ | --------------- | ---------- |
| **A. Base de pruebas en la nube** | Probar rápido la app con la API, sin instalar nada más | Internet |
| **B. Base local** | Cambiar migraciones o datos, o probar sin afectar a nadie | Docker Desktop (la primera descarga tarda) |

### Opción A: base de pruebas en la nube

Proyecto de Supabase `almacenes-itson-pruebas`, compartido por el equipo y **solo con datos de
prueba** (no captures datos reales). Ya tiene las 15 migraciones, `seed.sql`,
`seed_desarrollo.sql` y `seeds/entrega_demo.sql`.

En `servidor/.env`:

```env
SUPABASE_URL=https://ficapmexnfysnxhsfgzp.supabase.co
SUPABASE_ANON_KEY=sb_publishable_BgnzhpLVs6a9OmSNRYDusg_7MuFfZis
```

La clave es la publicable: está hecha para usarse fuera del servidor y los permisos los pone
RLS. Usuarios para entrar:

| Usuario | Contraseña | Rol y campus |
| ------- | ---------- | ------------ |
| `almacen.nainari@itson.mx` | `demo1234` | Almacenista, Náinari (escenario de ventanilla) |
| `supervisor.nainari@itson.mx` | `demo1234` | Supervisor, Náinari |
| `almacenista.centro@almacenes.test` | `Almacen-Dev-2026` | Almacenista, Centro (productos para paginar) |

Como es compartida, lo que registres (boletas, préstamos, existencias que bajan) lo ven los
demás y no se borra. Si los datos de ventanilla ya no sirven para probar, avisa en el equipo.
Cuando alguien agregue una migración en `supabase/migrations/`, también hay que aplicarla a este
proyecto; si no, el servidor puede fallar con columnas o funciones que no existen.

### Opción B: base local

La base de desarrollo corre en Docker con Supabase CLI. Desde la raíz del repo:

```bash
npx supabase start      # levanta PostgreSQL 17, API, Studio y storage
npx supabase db reset   # aplica las migraciones y carga los datos de desarrollo
```

`db reset` ejecuta `supabase/seed.sql` y `supabase/seed_desarrollo.sql` (ver `[db.seed]` en
`supabase/config.toml`). Para agregar el escenario de entrega en ventanilla, corre además
`supabase/seeds/entrega_demo.sql` (ver [Datos de ejemplo para ventanilla](#datos-de-ejemplo-para-ventanilla)).

Servicios locales:

| Servicio     | URL / conexión                                              |
| ------------ | ----------------------------------------------------------- |
| API Supabase | `http://127.0.0.1:54321`                                    |
| PostgreSQL   | `postgresql://postgres:postgres@127.0.0.1:54322/postgres`   |
| Studio       | `http://127.0.0.1:54323`                                    |

Copia las claves al servidor:

```bash
npx supabase status -o env    # muestra PUBLISHABLE_KEY y SECRET_KEY
```

En `servidor/.env`:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<PUBLISHABLE_KEY>
```

Para detener los servicios usa `npx supabase stop`; para reiniciar la base desde cero,
`npx supabase db reset`.

## Probar la app con la API en local

Requisitos: un emulador Android encendido (ver [INSTALACION.md](INSTALACION.md), paso 3) y
**Git Bash** (los comandos de abajo no funcionan en PowerShell). Abre las terminales en la raíz del repo.
Configura primero `servidor/.env` con una de las dos bases (ver [Elegir la base de datos](#elegir-la-base-de-datos));
con la base local, Docker Desktop debe estar abierto.

```bash
cd servidor && npm run start:dev    # terminal 1
cd app && flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1   # terminal 2
```

La primera compilación de Android puede tardar 10 minutos o más; el aviso "SDK XML version 4" no es
un error. Inicia sesión con `almacen.nainari@itson.mx` / `demo1234`.

## Datos de ejemplo para ventanilla

`supabase/seeds/entrega_demo.sql` carga un escenario completo para probar la entrega de
material (HU6) contra la base local: un almacenista y un supervisor con acceso a la app,
cuatro materiales con existencia, tres trabajadores, dos zonas con su límite y periodicidad,
y firmas de ejemplo en el bucket. Es idempotente (se puede correr varias veces).

```bash
# Desde la raíz del repo, en Git Bash. No necesitas psql instalado:
docker exec -i supabase_db_almacen_itson \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/seeds/entrega_demo.sql
```

Si el contenedor tiene otro nombre, encuéntralo con
`docker ps --filter name=supabase_db --format '{{.Names}}'`.

Los usuarios demo son `almacen.nainari@itson.mx` y `supervisor.nainari@itson.mx`
(contraseña `demo1234`). El encabezado del archivo explica cómo simular la entrega desde
la base local.

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
