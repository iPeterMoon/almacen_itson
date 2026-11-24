import {
  ArgumentsHost,
  BadRequestException,
  HttpStatus,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ErrorImportacion } from '../errores/error-importacion';
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

  afterEach(() => jest.restoreAllMocks());

  it('traduce ErrorNegocio a su estado y { codigo, mensaje }', () => {
    const { host, respuesta } = hostFalso();
    filtro.catch(new ErrorNegocio('STOCK_INSUFICIENTE', 'Solo hay 3.'), host);
    expect(respuesta.status).toHaveBeenCalledWith(409);
    expect(respuesta.json).toHaveBeenCalledWith({
      codigo: 'STOCK_INSUFICIENTE',
      mensaje: 'Solo hay 3.',
    });
  });

  it('traduce ErrorImportacion a 422 con { importadas: 0, errores }', () => {
    const { host, respuesta } = hostFalso();
    const errores = [{ fila: 4, motivo: 'La cantidad debe ser mayor a cero.' }];
    filtro.catch(new ErrorImportacion(errores), host);
    expect(respuesta.status).toHaveBeenCalledWith(422);
    expect(respuesta.json).toHaveBeenCalledWith({ importadas: 0, errores });
  });

  it('incluye los datos del ErrorNegocio cuando los trae', () => {
    const { host, respuesta } = hostFalso();
    const datos = { disponible: 4, cantidadSugerida: 4 };
    filtro.catch(new ErrorNegocio('STOCK_INSUFICIENTE', 'Solo hay 4.', undefined, datos), host);
    expect(respuesta.status).toHaveBeenCalledWith(409);
    expect(respuesta.json).toHaveBeenCalledWith({
      codigo: 'STOCK_INSUFICIENTE',
      mensaje: 'Solo hay 4.',
      datos,
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

  it('asocia el error con el id de correlación y la ruta de la petición', () => {
    const error = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const respuesta = { status: jest.fn().mockReturnThis(), json: jest.fn() };
    const peticion = {
      idCorrelacion: 'abcd1234',
      method: 'POST',
      originalUrl: '/api/v1/usuarios/sesion?token=secreto',
    };
    const host = {
      switchToHttp: () => ({
        getResponse: () => respuesta,
        getRequest: () => peticion,
      }),
    } as unknown as ArgumentsHost;

    filtro.catch(new Error('falló Supabase Auth'), host);

    const mensaje = error.mock.calls[0][0] as string;
    expect(mensaje).toContain('POST /api/v1/usuarios/sesion');
    expect(mensaje).toContain('id=abcd1234');
    expect(mensaje).toContain('falló Supabase Auth');
    expect(mensaje).not.toContain('token=secreto');
  });

  it('registra los errores de negocio con su código y la petición', () => {
    const aviso = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const { host, respuesta } = hostFalso();
    filtro.catch(
      new ErrorNegocio(
        'CREDENCIALES_INVALIDAS',
        'Correo o contraseña incorrectos.',
        HttpStatus.UNAUTHORIZED,
      ),
      host,
    );

    expect(respuesta.status).toHaveBeenCalledWith(401);
    expect(aviso).toHaveBeenCalledWith(expect.stringContaining('CREDENCIALES_INVALIDAS'));
  });
});
