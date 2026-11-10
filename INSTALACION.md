# Instalación del entorno de desarrollo

Guía para dejar lista una computadora (Windows 10/11) y trabajar en el proyecto.
Al final de cada paso hay un comando para comprobar que quedó bien.

## Resumen

| Herramienta          | Versión usada en el proyecto | Para qué                                  | ¿Quién la necesita?   |
| -------------------- | ---------------------------- | ----------------------------------------- | --------------------- |
| Git                  | cualquiera reciente          | Control de versiones                      | Todos                 |
| Node.js (LTS) + npm  | Node 24 (mínimo 22)          | Servidor NestJS                           | Todos                 |
| Flutter (stable)     | 3.47                         | App móvil                                 | Todos                 |
| Android Studio       | reciente                     | SDK de Android y emulador                 | Todos                 |
| Docker Desktop       | reciente                     | Imagen del servidor y Supabase local      | Opcional al inicio    |
| Supabase CLI         | reciente                     | Migraciones y base local                  | Quien toque la base   |
| VS Code              | reciente                     | Editor recomendado                        | Opcional              |

> Los comandos usan `winget`, que viene incluido en Windows 10/11. Ábrelos en **PowerShell**.
> Después de instalar algo, **cierra y vuelve a abrir la terminal** para que tome el nuevo `PATH`.

---

## 1. Git

```powershell
winget install --id Git.Git -e
git --version
```

Configura tu nombre y correo (el de tu cuenta de GitHub):

```powershell
git config --global user.name "Tu Nombre"
git config --global user.email "tu-correo@ejemplo.com"
```

Clona el repositorio:

```powershell
cd $HOME\Documents\GitHub
git clone https://github.com/iPeterMoon/almacen_itson.git
cd almacen_itson
```

## 2. Node.js (para el servidor)

```powershell
winget install --id OpenJS.NodeJS.LTS -e
node -v     # v22 o superior
npm -v
```

Instala las dependencias del servidor y comprueba que todo pasa:

```powershell
cd servidor
npm ci
npm run lint
npm test
npm run build
```

`npm ci` instala exactamente las versiones de `package-lock.json`. Usa `npm install <paquete>`
solo cuando el equipo acuerde agregar un paquete nuevo.

## 3. Android Studio (SDK y emulador)

```powershell
winget install --id Google.AndroidStudio -e
```

1. Abre Android Studio y sigue el asistente con la opción **Standard** (instala el SDK, las
   herramientas de plataforma y un JDK).
2. En **More Actions → SDK Manager → SDK Tools**, marca **Android SDK Command-line Tools** y aplica.
3. En **More Actions → Virtual Device Manager**, crea un emulador (por ejemplo, un Pixel con la
   imagen de Android más reciente).

Si prefieres un teléfono físico: activa **Opciones de desarrollador → Depuración USB** y conéctalo.

## 4. Flutter (para la app)

1. Descarga el SDK de Flutter **stable** para Windows desde <https://docs.flutter.dev/get-started/install/windows>.
2. Descomprímelo en una ruta **sin espacios ni acentos**, por ejemplo `C:\src\flutter`.
3. Agrega `C:\src\flutter\bin` al `PATH`:
   *Inicio → "Editar las variables de entorno de esta cuenta" → Path → Editar → Nuevo*.
4. Abre una terminal nueva y ejecuta:

```powershell
flutter --version
flutter doctor --android-licenses   # acepta todas con "y"
flutter doctor
```

`flutter doctor` debe salir con palomita en **Flutter**, **Android toolchain** y
**Android Studio**. Lo de Chrome, Visual Studio o iOS no hace falta (la app es solo Android).

Comprueba la app:

```powershell
cd app
flutter pub get
flutter analyze
flutter test
```

## 5. Docker Desktop (opcional al inicio)

Se usa para construir la imagen del servidor y para levantar Supabase en tu computadora.

```powershell
winget install --id Docker.DockerDesktop -e
```

Reinicia la computadora si lo pide, abre Docker Desktop y espera a que diga *Engine running*.

```powershell
docker --version
cd servidor
docker build -t almacenes-itson-servidor .
```

## 6. Supabase CLI (quien trabaje con la base)

La forma más simple es usarla con `npx`, sin instalar nada global:

```powershell
npx supabase --version
```

O instálala con Scoop:

```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
supabase --version
```

> La configuración local está en `supabase/config.toml`. Para levantarla:
>
> ```powershell
> npx supabase start
> npx supabase stop
> ```
>
> `supabase start` aplica las migraciones de `supabase/migrations` y el `seed.sql`.

Reglas para migraciones:

- Crea las nuevas con `supabase migration new <nombre>`; **no renombres** las existentes
  (el número del inicio es la versión que la base registra como aplicada).
- No edites una migración que ya se aplicó en el proyecto compartido; crea una nueva.
- Después de cambiar una migración, regenera los tipos de TypeScript:

  ```powershell
  cd servidor
  npm run gen:types
  ```

  El comando requiere que Supabase local esté corriendo (`npx supabase start`). Genera
  `servidor/src/supabase/tipos-base.ts` a partir del esquema `public`.

## 7. VS Code (opcional)

```powershell
winget install --id Microsoft.VisualStudioCode -e
```

Extensiones recomendadas: **Flutter**, **Dart**, **ESLint**, **Prettier** y
**PostgreSQL** (o *SQLTools*) para leer las migraciones.

---

## Variables de entorno del servidor

```powershell
cd servidor
copy .env.example .env
```

Llena en `servidor/.env`:

| Variable            | De dónde sale                                                              |
| ------------------- | -------------------------------------------------------------------------- |
| `SUPABASE_URL`      | Panel de Supabase → proyecto *almacenes-itson* → Project Settings → API    |
| `SUPABASE_ANON_KEY` | Mismo lugar: la clave **publicable / anon** (nunca la `service_role`)      |
| `PUERTO`            | Opcional, por defecto `3000`                                               |
| `CORS_ORIGENES`     | Opcional, déjalo vacío para la app móvil                                   |

El archivo `.env` **nunca se sube** al repositorio (está en `.gitignore`). Si no tienes acceso al
panel de Supabase, pide los valores al equipo por un canal privado.

## Levantar todo

Terminal 1, servidor:

```powershell
cd servidor
npm run start:dev
```

Abre <http://localhost:3000/api/v1/salud> (debe responder `{"estado":"ok", ...}`) y
<http://localhost:3000/docs> (documentación de la API).

Terminal 2, app (con el emulador abierto):

```powershell
cd app
flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1
```

`10.0.2.2` es como el emulador de Android llama a `localhost` de tu computadora. En un teléfono
físico usa la IP de tu computadora en la red local (por ejemplo `http://192.168.1.50:3000/api/v1`)
y asegúrate de que el firewall de Windows permita el puerto 3000.

## Problemas comunes

| Síntoma                                                     | Solución                                                                        |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `flutter` / `node` no se reconoce como comando              | Cierra y abre la terminal; revisa que la carpeta esté en el `PATH`.             |
| El servidor no arranca: *Variables de entorno inválidas*    | Falta `servidor/.env` o le faltan `SUPABASE_URL` / `SUPABASE_ANON_KEY`.         |
| `flutter doctor` marca *Android license status unknown*     | `flutter doctor --android-licenses` y acepta todo.                              |
| `docker build` dice que no se puede conectar al daemon      | Abre Docker Desktop y espera a *Engine running*.                                |
| La app en el emulador no llega al servidor                  | Usa `10.0.2.2`, no `localhost`, en `API_URL`.                                   |
