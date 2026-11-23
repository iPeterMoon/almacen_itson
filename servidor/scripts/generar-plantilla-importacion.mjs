// Genera la plantilla de ejemplo de la HU11. Se versiona el .xlsx resultante
// para que el equipo pueda descargarlo sin instalar nada; este script solo se
// usa si hay que regenerarlo tras cambiar las columnas.
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ExcelJS from 'exceljs';

const raizServidor = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const destino = resolve(raizServidor, 'plantillas/plantilla-importar-entregas.xlsx');

const columnas = [
  'folio',
  'fecha',
  'solicitante',
  'dependencia',
  'código de material',
  'cantidad',
  'almacén',
];

const filas = [
  ['BOL-2025-0001', '2025-03-04', 'Miguel Ángel Ruiz', 'Servicios Generales', 'JAB-001', 2, 'Principal'],
  ['BOL-2025-0001', '2025-03-04', 'Miguel Ángel Ruiz', 'Servicios Generales', 'PAP-010', 5, 'Principal'],
  ['BOL-2025-0002', '04/03/2025', 'Ana López', 'Mantenimiento', 'JAB-001', 1, 'Principal'],
];

const libro = new ExcelJS.Workbook();
libro.creator = 'Almacenes ITSON';
const hoja = libro.addWorksheet('Entregas');
hoja.addRow(columnas);
for (const fila of filas) hoja.addRow(fila);

hoja.getRow(1).font = { bold: true };
hoja.getRow(1).alignment = { vertical: 'middle' };
hoja.columns = [
  { width: 18 },
  { width: 14 },
  { width: 24 },
  { width: 22 },
  { width: 22 },
  { width: 12 },
  { width: 16 },
];
hoja.views = [{ state: 'frozen', ySplit: 1 }];

mkdirSync(dirname(destino), { recursive: true });
await libro.xlsx.writeFile(destino);
console.log(`Plantilla generada en ${destino}`);
