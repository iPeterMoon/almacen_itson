// Va en setupFiles porque AppModule valida el entorno al importarse.
// Lee .env.pruebas (o .env si no existe) y se niega a correr contra otra base: estas
// pruebas escriben boletas, préstamos y firmas que no se pueden borrar.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseEnv } from 'node:util';

// Proyecto almacenes-itson-pruebas y Supabase local. Nunca el proyecto principal.
const HOSTS_PERMITIDOS = ['ficapmexnfysnxhsfgzp.supabase.co', '127.0.0.1', 'localhost'];

const raiz = join(__dirname, '..', '..');
const archivo = ['.env.pruebas', '.env'].find((nombre) => existsSync(join(raiz, nombre)));
const variables = archivo ? parseEnv(readFileSync(join(raiz, archivo), 'utf8')) : {};

// Las variables ya definidas en la terminal tienen prioridad sobre el archivo.
const url = process.env.SUPABASE_URL ?? variables.SUPABASE_URL ?? '';
const clave = process.env.SUPABASE_ANON_KEY ?? variables.SUPABASE_ANON_KEY ?? '';
if (!url || !clave) {
  throw new Error(
    'Faltan SUPABASE_URL y SUPABASE_ANON_KEY: crea servidor/.env.pruebas (ver README).',
  );
}

const host = URL.canParse(url) ? new URL(url).hostname : url;
if (!HOSTS_PERMITIDOS.includes(host)) {
  throw new Error(
    `Las pruebas de integración solo corren contra la base de pruebas o la local, no contra "${host}".`,
  );
}

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = url;
process.env.SUPABASE_ANON_KEY = clave;
