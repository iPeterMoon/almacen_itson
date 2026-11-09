import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UsuarioSesionRepository } from '../autenticacion/usuario-sesion.repository';
import { ES_PUBLICA } from '../decoradores/publica.decorator';
import { ROLES } from '../decoradores/roles.decorator';
import { PeticionConUsuario, Rol } from '../tipos/usuario-autenticado';
import { extraerToken, JwtAuthGuard } from './jwt-auth.guard';
import { RolesGuard } from './roles.guard';

function contexto(peticion: PeticionConUsuario): ExecutionContext {
  return {
    getHandler: () => undefined,
    getClass: () => undefined,
    switchToHttp: () => ({ getRequest: () => peticion }),
  } as unknown as ExecutionContext;
}

function reflectorCon(metadatos: Record<string, unknown>): Reflector {
  return { getAllAndOverride: (clave: string) => metadatos[clave] } as unknown as Reflector;
}

const usuarioBase = { id: 'u1', nombre: 'Ana', rol: Rol.Almacenista, campusId: 1, activo: true };

describe('extraerToken', () => {
  it('lee el token Bearer', () => {
    expect(extraerToken('Bearer abc')).toBe('abc');
    expect(extraerToken('bearer abc')).toBe('abc');
  });

  it('rechaza cabeceras ausentes o con otro esquema', () => {
    expect(extraerToken(undefined)).toBeNull();
    expect(extraerToken('Basic abc')).toBeNull();
    expect(extraerToken('Bearer')).toBeNull();
  });
});

describe('JwtAuthGuard', () => {
  let repositorio: { idDeToken: jest.Mock; buscarPorId: jest.Mock };
  const crear = (metadatos: Record<string, unknown> = {}) =>
    new JwtAuthGuard(reflectorCon(metadatos), repositorio as unknown as UsuarioSesionRepository);
  const conToken = (): PeticionConUsuario => ({ headers: { authorization: 'Bearer t' } });

  beforeEach(() => {
    repositorio = { idDeToken: jest.fn(), buscarPorId: jest.fn() };
  });

  it('deja pasar rutas @Publica() sin token', async () => {
    await expect(
      crear({ [ES_PUBLICA]: true }).canActivate(contexto({ headers: {} })),
    ).resolves.toBe(true);
    expect(repositorio.idDeToken).not.toHaveBeenCalled();
  });

  it('responde 401 sin token', async () => {
    await expect(crear().canActivate(contexto({ headers: {} }))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('responde 401 si Supabase rechaza el token', async () => {
    repositorio.idDeToken.mockResolvedValue(null);
    await expect(crear().canActivate(contexto(conToken()))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('responde 403 si el usuario no está en public.usuarios', async () => {
    repositorio.idDeToken.mockResolvedValue('u1');
    repositorio.buscarPorId.mockResolvedValue(null);
    await expect(crear().canActivate(contexto(conToken()))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('responde 403 si el usuario está inactivo', async () => {
    repositorio.idDeToken.mockResolvedValue('u1');
    repositorio.buscarPorId.mockResolvedValue({ ...usuarioBase, activo: false });
    await expect(crear().canActivate(contexto(conToken()))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('deja en la petición el usuario con rol, campus y token', async () => {
    repositorio.idDeToken.mockResolvedValue('u1');
    repositorio.buscarPorId.mockResolvedValue(usuarioBase);
    const peticion = conToken();
    await expect(crear().canActivate(contexto(peticion))).resolves.toBe(true);
    expect(peticion.usuario).toEqual({
      id: 'u1',
      nombre: 'Ana',
      rol: Rol.Almacenista,
      campusId: 1,
      token: 't',
    });
  });
});

describe('RolesGuard', () => {
  const peticion: PeticionConUsuario = {
    headers: {},
    usuario: { id: 'u1', nombre: 'Ana', rol: Rol.Almacenista, campusId: 1, token: 't' },
  };

  it('deja pasar si la ruta no declara roles', () => {
    expect(new RolesGuard(reflectorCon({})).canActivate(contexto(peticion))).toBe(true);
  });

  it('deja pasar si el rol está permitido', () => {
    const guardia = new RolesGuard(reflectorCon({ [ROLES]: [Rol.Almacenista, Rol.Supervisor] }));
    expect(guardia.canActivate(contexto(peticion))).toBe(true);
  });

  it('responde 403 si el rol no está permitido', () => {
    const guardia = new RolesGuard(reflectorCon({ [ROLES]: [Rol.Admin] }));
    expect(() => guardia.canActivate(contexto(peticion))).toThrow(ForbiddenException);
  });
});
