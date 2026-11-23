// Solo pruebas: construye un XLSX en memoria con la plantilla de la HU11.
import ExcelJS from 'exceljs';

export const CABECERA_XLSX = [
  'folio',
  'fecha',
  'solicitante',
  'dependencia',
  'código de material',
  'cantidad',
  'almacén',
];

export type FilaXlsx = (string | number | null)[];

export async function crearXlsx(
  filas: FilaXlsx[],
  cabecera: string[] = CABECERA_XLSX,
): Promise<Buffer> {
  const libro = new ExcelJS.Workbook();
  const hoja = libro.addWorksheet('Entregas');
  hoja.addRow(cabecera);
  for (const fila of filas) hoja.addRow(fila);
  return (await libro.xlsx.writeBuffer()) as unknown as Buffer;
}
