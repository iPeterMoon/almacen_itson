import { HttpStatus } from '@nestjs/common';

// Un renglón del Excel que no pasó la validación. `fila` es el número real de
// fila de la hoja (la cabecera es la fila 1), para que quien importa pueda
// localizar el error en su archivo.
export interface ErrorFilaImportacion {
  fila: number;
  motivo: string;
}

// CUERPO: { importadas: 0, errores: [{ fila, motivo }] }, con HTTP 422.
// Es distinto de ErrorNegocio: la HU pide este formato exacto y no el
// sobre { codigo, mensaje } que usa el resto de la API.
export class ErrorImportacion extends Error {
  readonly estadoHttp: HttpStatus = HttpStatus.UNPROCESSABLE_ENTITY;

  constructor(readonly errores: ErrorFilaImportacion[]) {
    super('El archivo contiene filas inválidas.');
    this.name = 'ErrorImportacion';
  }
}
