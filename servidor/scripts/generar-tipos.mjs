import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Genera el archivo de tipos desde la base local. Requiere `supabase start`.
// Se escribe al final para no dejar el archivo vacío si la generación falla.
const raizServidor = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const raizRepo = resolve(raizServidor, '..');
const destino = resolve(raizServidor, 'src/supabase/tipos-base.ts');

const salida = execSync(
  `npx supabase --workdir "${raizRepo}" gen types typescript --local --schema public`,
  { cwd: raizServidor, encoding: 'utf8' },
);

writeFileSync(destino, salida);
console.log(`Tipos generados en ${destino}`);
