// HU11: lectura y validación del Excel de entregas anteriores. Toda la forma del
// archivo se revisa aquí, antes de llamar a la RPC: si una fila está mal, se
// lanza ErrorImportacion con TODOS los errores y no se importa nada.
import { HttpStatus } from '@nestjs/common';
import ExcelJS from 'exceljs';
import { LARGO_NOMBRE, LARGO_REFERENCIA } from '../../../comun/dto/limites';
import { ErrorNegocio } from '../../../comun/errores/error-negocio';
import { ErrorFilaImportacion, ErrorImportacion } from '../../../comun/errores/error-importacion';

// Columnas obligatorias de la plantilla HU11 (7). Cualquier columna adicional
// se ignora: las entregas anteriores solo traen materiales, no préstamos.
export const COLUMNAS_PLANTILLA = [
  'folio',
  'fecha',
  'solicitante',
  'dependencia',
  'código de material',
  'cantidad',
  'almacén',
] as const;

export const MAX_FILAS_DATOS = 1000;

export interface MaterialImportado {
  fila: number;
  codigo: string;
  cantidad: number;
}

export interface BoletaImportada {
  fila: number;
  folio: string;
  fecha: string;
  solicitante: string;
  dependencia: string;
  almacen: string;
  materiales: MaterialImportado[];
}

// Acepta "código" y "codigo", con o sin mayúsculas y con espacios de más.
function normalizar(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');
}

function textoCelda(valor: ExcelJS.CellValue): string {
  if (valor === null || valor === undefined) return '';
  if (valor instanceof Date) return valor.toISOString().slice(0, 10);
  if (typeof valor === 'string') return valor.trim();
  if (typeof valor === 'number' || typeof valor === 'boolean') return String(valor);
  if (Array.isArray(valor)) return valor.map(textoCelda).join('').trim();
  if (typeof valor === 'object') {
    if ('richText' in valor)
      return valor.richText
        .map((t) => t.text)
        .join('')
        .trim();
    if ('result' in valor) return textoCelda(valor.result);
    if ('text' in valor) return String(valor.text).trim();
  }
  return '';
}

// null = celda vacía; NaN = celda con un valor que no es entero.
function entero(valor: ExcelJS.CellValue): number | null {
  const texto = textoCelda(valor);
  if (texto === '') return null;
  if (!/^\d+$/.test(texto)) return NaN;
  const numero = Number(texto);
  return Number.isSafeInteger(numero) ? numero : NaN;
}

function fechaISO(valor: ExcelJS.CellValue): string | null {
  if (valor instanceof Date) {
    return validarFecha(valor.getUTCFullYear(), valor.getUTCMonth() + 1, valor.getUTCDate());
  }
  const texto = textoCelda(valor);
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto);
  if (iso) return validarFecha(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const latina = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto);
  if (latina) return validarFecha(Number(latina[3]), Number(latina[2]), Number(latina[1]));
  return null;
}

function validarFecha(anio: number, mes: number, dia: number): string | null {
  const fecha = new Date(Date.UTC(anio, mes - 1, dia));
  if (
    fecha.getUTCFullYear() !== anio ||
    fecha.getUTCMonth() + 1 !== mes ||
    fecha.getUTCDate() !== dia
  ) {
    return null;
  }
  return `${anio}-${String(mes).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

function esZip(valor: Buffer): boolean {
  return (
    valor.length >= 4 &&
    valor[0] === 0x50 &&
    valor[1] === 0x4b &&
    ((valor[2] === 0x03 && valor[3] === 0x04) || (valor[2] === 0x05 && valor[3] === 0x06))
  );
}

// Lee la primera hoja y devuelve las boletas agrupadas por folio. Los errores
// de archivo (no XLSX, corrupto) son 400 con { codigo, mensaje }; los errores
// de cabecera o de fila son 422 con { importadas, errores }.
export async function leerPlantilla(datos: Buffer): Promise<BoletaImportada[]> {
  if (!esZip(datos)) {
    throw new ErrorNegocio(
      'ARCHIVO_INVALIDO',
      'El archivo debe ser un XLSX válido.',
      HttpStatus.BAD_REQUEST,
    );
  }

  const libro = new ExcelJS.Workbook();
  type DatosXlsx = Parameters<typeof libro.xlsx.load>[0];
  try {
    await libro.xlsx.load(datos as unknown as DatosXlsx);
  } catch {
    throw new ErrorNegocio(
      'ARCHIVO_INVALIDO',
      'No se pudo leer el archivo XLSX.',
      HttpStatus.BAD_REQUEST,
    );
  }
  const hoja = libro.worksheets[0];
  if (!hoja) {
    throw new ErrorNegocio(
      'ARCHIVO_INVALIDO',
      'El archivo no tiene hojas.',
      HttpStatus.BAD_REQUEST,
    );
  }

  // Cabecera: se admiten las 7 columnas en cualquier orden; las extras se
  // ignoran, pero ninguna de las 7 puede faltar ni repetirse.
  const indices = new Map<string, number>();
  const erroresCabecera: ErrorFilaImportacion[] = [];
  for (let columna = 1; columna <= hoja.columnCount; columna++) {
    const nombre = normalizar(textoCelda(hoja.getRow(1).getCell(columna).value));
    if (!nombre) continue;
    if (indices.has(nombre)) {
      erroresCabecera.push({ fila: 1, motivo: `La columna "${nombre}" está repetida.` });
    } else {
      indices.set(nombre, columna);
    }
  }
  for (const columna of COLUMNAS_PLANTILLA) {
    if (!indices.has(normalizar(columna))) {
      erroresCabecera.push({ fila: 1, motivo: `Falta la columna "${columna}".` });
    }
  }
  if (erroresCabecera.length > 0) throw new ErrorImportacion(erroresCabecera);

  const errores: ErrorFilaImportacion[] = [];
  const porFolio = new Map<string, BoletaImportada>();
  let filasDatos = 0;

  for (let fila = 2; fila <= hoja.rowCount; fila++) {
    const filaExcel = hoja.getRow(fila);
    const valor = (columna: string): ExcelJS.CellValue =>
      filaExcel.getCell(indices.get(normalizar(columna))!).value;
    const texto = (columna: string): string => textoCelda(valor(columna));

    // Las filas vacías al final del archivo no cuentan como datos.
    if (COLUMNAS_PLANTILLA.every((columna) => textoCelda(valor(columna)) === '')) continue;
    filasDatos++;
    if (filasDatos > MAX_FILAS_DATOS) {
      throw new ErrorImportacion([
        {
          fila,
          motivo: `El archivo supera el máximo de ${MAX_FILAS_DATOS} filas de datos.`,
        },
      ]);
    }

    const erroresFila: ErrorFilaImportacion[] = [];
    const fallar = (motivo: string) => erroresFila.push({ fila, motivo });

    const folio = texto('folio');
    const fecha = fechaISO(valor('fecha'));
    const solicitante = texto('solicitante');
    const dependencia = texto('dependencia');
    const almacen = texto('almacén');
    const codigoMaterial = texto('código de material');
    const cantidad = entero(valor('cantidad'));

    if (!folio) fallar('El folio es obligatorio.');
    else if (folio.length > LARGO_REFERENCIA) fallar('El folio es demasiado largo.');
    if (!fecha) fallar('La fecha debe estar en formato AAAA-MM-DD o DD/MM/AAAA.');
    if (!solicitante) fallar('El solicitante es obligatorio.');
    else if (solicitante.length > LARGO_NOMBRE) fallar('El solicitante es demasiado largo.');
    if (!dependencia) fallar('La dependencia es obligatoria.');
    else if (dependencia.length > LARGO_NOMBRE) fallar('La dependencia es demasiado larga.');
    if (!almacen) fallar('El almacén es obligatorio.');
    else if (almacen.length > LARGO_NOMBRE) fallar('El almacén es demasiado largo.');

    if (!codigoMaterial) fallar('El código de material es obligatorio.');
    else if (codigoMaterial.length > LARGO_REFERENCIA) {
      fallar('El código de material es demasiado largo.');
    }
    if (cantidad === null) fallar('La cantidad es obligatoria.');
    else if (!Number.isInteger(cantidad) || cantidad < 1) {
      fallar('La cantidad debe ser un número entero mayor a cero.');
    }

    if (erroresFila.length > 0) {
      errores.push(...erroresFila);
      continue;
    }

    const clave = folio.toUpperCase();
    let boleta = porFolio.get(clave);
    if (!boleta) {
      boleta = {
        fila,
        folio,
        fecha: fecha!,
        solicitante,
        dependencia,
        almacen,
        materiales: [],
      };
      porFolio.set(clave, boleta);
    } else {
      const cambia: string[] = [];
      if (normalizar(boleta.fecha) !== normalizar(fecha!)) cambia.push('fecha');
      if (normalizar(boleta.solicitante) !== normalizar(solicitante)) cambia.push('solicitante');
      if (normalizar(boleta.dependencia) !== normalizar(dependencia)) cambia.push('dependencia');
      if (normalizar(boleta.almacen) !== normalizar(almacen)) cambia.push('almacén');
      if (cambia.length > 0) {
        fallar(`El folio ${folio} tiene ${cambia.join(', ')} distinto(s) de la primera fila.`);
        errores.push(...erroresFila);
        continue;
      }
    }

    boleta.materiales.push({ fila, codigo: codigoMaterial, cantidad: cantidad! });
  }

  if (errores.length > 0) throw new ErrorImportacion(errores);
  if (filasDatos === 0) {
    throw new ErrorImportacion([{ fila: 1, motivo: 'El archivo no tiene filas de datos.' }]);
  }
  return [...porFolio.values()];
}
