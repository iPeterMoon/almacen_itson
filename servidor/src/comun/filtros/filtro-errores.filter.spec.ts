import { ArgumentsHost, BadRequestException, Logger, NotFoundException } from '@nestjs/common';
import { ErrorNegocio } from '../errores/error-negocio';
import { FiltroErrores } from './filtro-errores.filter';

function hostFalso() {
  const respuesta = { status: jest.fn().mockReturnThis(), json: jest.fn() };
  const host = {
    switchToHttp: () => ({ getResponse: () => respuesta }),
  } as unknown as ArgumentsHost;
  return { host, respuesta };
}

describe('FiltroErrores', () => {
  const filtro = new FiltroErrores();

  it('traduce ErrorNegocio a su estado y { codigo, mensaje }', () => {
    const { host, respuesta } = hostFalso();
    filtro.catch(new ErrorNegocio('STOCK_INSUFICIENTE', 'Solo hay 3.'), host);
    expect(respuesta.status).toHaveBeenCalledWith(409);
    expect(respuesta.json).toHaveBeenCalledWith({
      codigo: 'STOCK_INSUFICIENTE',
      mensaje: 'Solo hay 3.',
    });
  });

  it('incluye los detalles de validación del ValidationPipe', () => {
    const { host, respuesta } = hostFalso();
    filtro.catch(new BadRequestException(['cantidad must be a number']), host);
    expect(respuesta.status).toHaveBeenCalledWith(400);
    expect(respuesta.json).toHaveBeenCalledWith({
      codigo: 'PETICION_INVALIDA',
      mensaje: 'La petición tiene datos inválidos.',
      detalles: ['cantidad must be a number'],
    });
  });

  it('traduce HttpException simples', () => {
    const { host, respuesta } = hostFalso();
    filtro.catch(new NotFoundException('No existe.'), host);
    expect(respuesta.status).toHaveBeenCalledWith(404);
    expect(respuesta.json).toHaveBeenCalledWith({ codigo: 'NO_ENCONTRADO', mensaje: 'No existe.' });
  });

  it('oculta los detalles de errores inesperados', () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const { host, respuesta } = hostFalso();
    filtro.catch(new Error('password=secreto en la cadena de conexión'), host);
    expect(respuesta.status).toHaveBeenCalledWith(500);
    const cuerpo = (respuesta.json.mock.calls[0] as unknown[])[0];
    expect(cuerpo).toMatchObject({ codigo: 'ERROR_INTERNO' });
    expect(JSON.stringify(cuerpo)).not.toContain('secreto');
  });
});
