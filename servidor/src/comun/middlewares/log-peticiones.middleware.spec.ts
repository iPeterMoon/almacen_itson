import { Logger } from '@nestjs/common';
import { EventEmitter } from 'node:events';
import type { NextFunction, Response } from 'express';
import { Rol } from '../tipos/usuario-autenticado';
import {
  CABECERA_CORRELACION,
  PeticionConCorrelacion,
  registrarLogsPeticiones,
} from './log-peticiones.middleware';

function peticion(url = '/api/v1/usuarios/sesion'): PeticionConCorrelacion {
  return { method: 'POST', originalUrl: url, url, body: {} } as PeticionConCorrelacion;
}

function respuesta(statusCode = 200) {
  const res = new EventEmitter() as EventEmitter & {
    statusCode: number;
    setHeader: jest.Mock;
  };
  res.statusCode = statusCode;
  res.setHeader = jest.fn();
  return res;
}

describe('registrarLogsPeticiones', () => {
  afterEach(() => jest.restoreAllMocks());

  it('registra la entrada y la salida con método, ruta, estado, duración e id', () => {
    const inicio = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    const req = peticion();
    const res = respuesta();
    const siguiente = jest.fn() as NextFunction;

    registrarLogsPeticiones(req, res as unknown as Response, siguiente);
    res.emit('finish');

    expect(siguiente).toHaveBeenCalledTimes(1);
    expect(req.idCorrelacion).toHaveLength(8);
    expect(res.setHeader).toHaveBeenCalledWith(CABECERA_CORRELACION, req.idCorrelacion);
    expect(inicio).toHaveBeenCalledTimes(2);
    expect(inicio.mock.calls[0][0]).toContain('→ POST /api/v1/usuarios/sesion');
    expect(inicio.mock.calls[1][0]).toMatch(
      new RegExp(`\\[${req.idCorrelacion}\\] POST /api/v1/usuarios/sesion 200 \\d+ms`),
    );
  });

  it('no registra la cadena de consulta ni el cuerpo de la petición', () => {
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    const req = {
      ...peticion('/api/v1/usuarios/sesion?token=secreto'),
      body: { contrasena: 'abc' },
    };
    const res = respuesta();

    registrarLogsPeticiones(req, res as unknown as Response, jest.fn());
    res.emit('finish');

    const escrito = JSON.stringify(log.mock.calls);
    expect(escrito).toContain('/api/v1/usuarios/sesion');
    expect(escrito).not.toContain('token=secreto');
    expect(escrito).not.toContain('abc');
  });

  it.each([
    [401, 'warn'],
    [500, 'error'],
  ])('usa el nivel %s para las respuestas %i', (estado, _nivel) => {
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    const aviso = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const error = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const res = respuesta(estado);

    registrarLogsPeticiones(peticion(), res as unknown as Response, jest.fn());
    res.emit('finish');

    expect(log).toHaveBeenCalledTimes(1);
    expect(aviso).toHaveBeenCalledTimes(estado === 401 ? 1 : 0);
    expect(error).toHaveBeenCalledTimes(estado === 500 ? 1 : 0);
    expect(estado === 401 ? aviso : error).toHaveBeenCalledWith(
      expect.stringContaining(`POST /api/v1/usuarios/sesion ${estado}`),
    );
  });

  it('incluye el usuario autenticado cuando el guardia ya lo dejó en la petición', () => {
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    const req = peticion('/api/v1/ventanilla/materiales');
    req.usuario = {
      id: 'u1',
      nombre: 'Ana',
      rol: Rol.Almacenista,
      campusId: 1,
      token: 'no-loguear',
    };
    const res = respuesta();

    registrarLogsPeticiones(req, res as unknown as Response, jest.fn());
    res.emit('finish');

    expect(log.mock.calls[1][0]).toContain('usuario=u1');
    expect(JSON.stringify(log.mock.calls)).not.toContain('no-loguear');
  });
});
