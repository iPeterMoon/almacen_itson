import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio, estadoHttpDeCodigo, parsearErrorBase } from './error-negocio';

describe('parsearErrorBase', () => {
  it('separa código y mensaje de un error de PostgreSQL', () => {
    const error = parsearErrorBase('STOCK_INSUFICIENTE: Solo hay 3 piezas.');
    expect(error).toBeInstanceOf(ErrorNegocio);
    expect(error?.codigo).toBe('STOCK_INSUFICIENTE');
    expect(error?.message).toBe('Solo hay 3 piezas.');
    expect(error?.estadoHttp).toBe(HttpStatus.CONFLICT);
  });

  it('devuelve null si el mensaje no sigue el formato CODIGO: mensaje', () => {
    expect(parsearErrorBase('duplicate key value violates unique constraint')).toBeNull();
    expect(parsearErrorBase('')).toBeNull();
    expect(parsearErrorBase(undefined)).toBeNull();
  });
});

describe('estadoHttpDeCodigo', () => {
  it.each([
    ['SIN_PERMISO', HttpStatus.FORBIDDEN],
    ['CAMPUS_DISTINTO', HttpStatus.FORBIDDEN],
    ['PRODUCTO_NO_REGISTRADO', HttpStatus.NOT_FOUND],
    ['BOLETA_NO_EXISTE', HttpStatus.NOT_FOUND],
    ['ACTIVO_PRESTADO', HttpStatus.CONFLICT],
    ['REINGRESO_EXCEDE', HttpStatus.CONFLICT],
    ['FIRMA_INVALIDA', HttpStatus.UNPROCESSABLE_ENTITY],
    ['CANTIDAD_INVALIDA', HttpStatus.UNPROCESSABLE_ENTITY],
    ['CODIGO_NUEVO_DESCONOCIDO', HttpStatus.UNPROCESSABLE_ENTITY],
  ])('%s -> %d', (codigo, estado) => {
    expect(estadoHttpDeCodigo(codigo)).toBe(estado);
  });
});
