import { HttpStatus } from '@nestjs/common';

export class ErrorNegocio extends Error {
  // `datos` es opcional: detalles estructurados para que la app reaccione sin leer el texto
  // (por ejemplo, la existencia disponible en STOCK_INSUFICIENTE). Para pasarlo sin cambiar
  // el estado HTTP, usa `undefined` en el tercer parámetro.
  constructor(
    readonly codigo: string,
    mensaje: string,
    readonly estadoHttp: HttpStatus = estadoHttpDeCodigo(codigo),
    readonly datos?: Record<string, unknown>,
  ) {
    super(mensaje);
    this.name = 'ErrorNegocio';
  }
}

// Códigos que lanzan las funciones de supabase/migrations. Uno que no esté aquí responde 422.
const CODIGOS_POR_ESTADO: Record<number, readonly string[]> = {
  [HttpStatus.FORBIDDEN]: ['SIN_PERMISO', 'CAMPUS_DISTINTO'],
  [HttpStatus.NOT_FOUND]: [
    'ACTIVO_NO_ENCONTRADO',
    'ALMACEN_NO_EXISTE',
    'AUTORIZACION_NO_EXISTE',
    'BOLETA_NO_EXISTE',
    'FIRMA_NO_ENCONTRADA',
    'PRESTAMO_NO_EXISTE',
    'PRODUCTO_NO_REGISTRADO',
    'SOLICITANTE_NO_EXISTE',
  ],
  [HttpStatus.CONFLICT]: [
    'ACTIVO_DUPLICADO',
    'ACTIVO_NO_DISPONIBLE',
    'ACTIVO_PRESTADO',
    'AUTORIZACION_RESUELTA',
    'BOLETA_NO_AUTORIZADA',
    'BOLETA_NO_ENTREGADA',
    'PRESTAMO_CERRADO',
    'REINGRESO_EXCEDE',
    'SIN_CAMBIO',
    'SIN_DIFERENCIA',
    'STOCK_INSUFICIENTE',
  ],
};

const ESTADO_POR_CODIGO = new Map<string, HttpStatus>(
  Object.entries(CODIGOS_POR_ESTADO).flatMap(([estado, codigos]) =>
    codigos.map((c) => [c, Number(estado) as HttpStatus] as const),
  ),
);

export function estadoHttpDeCodigo(codigo: string): HttpStatus {
  return ESTADO_POR_CODIGO.get(codigo) ?? HttpStatus.UNPROCESSABLE_ENTITY;
}

const PATRON_ERROR_BASE = /^([A-Z][A-Z0-9_]*):\s*([\s\S]+)$/;

export function parsearErrorBase(mensaje: string | undefined | null): ErrorNegocio | null {
  if (!mensaje) return null;
  const coincidencia = PATRON_ERROR_BASE.exec(mensaje.trim());
  if (!coincidencia) return null;
  return new ErrorNegocio(coincidencia[1], coincidencia[2].trim());
}
