import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import { SesionRepository, TokensSupabase } from './sesion.repository';
import { SesionService } from './sesion.service';

const TOKENS: TokensSupabase = {
  accessToken: 'token-acceso',
  refreshToken: 'token-renovacion',
  expiraEn: 1763000000,
  usuarioId: 'u1',
  email: 'almacen.nainari@itson.mx',
};

const PERFIL = {
  id: 'u1',
  nombre: 'Almacén Náinari (demo)',
  rol: Rol.Almacenista,
  campusId: 1,
  campus: 'Náinari',
  activo: true,
};

// Repositorio falso: el servicio solo orquesta tokens + perfil.
function crearServicio(repositorio: {
  iniciarSesion?: jest.Mock;
  renovar?: jest.Mock;
  buscarPerfil?: jest.Mock;
}): SesionService {
  return new SesionService({
    iniciarSesion: jest.fn().mockResolvedValue(TOKENS),
    renovar: jest.fn().mockResolvedValue(TOKENS),
    buscarPerfil: jest.fn().mockResolvedValue(PERFIL),
    ...repositorio,
  } as unknown as SesionRepository);
}

describe('SesionService', () => {
  it('inicia sesión y devuelve los tokens con el perfil del usuario', async () => {
    const repositorio = {
      iniciarSesion: jest.fn().mockResolvedValue(TOKENS),
      buscarPerfil: jest.fn().mockResolvedValue(PERFIL),
    };

    const respuesta = await crearServicio(repositorio).iniciar({
      usuario: 'almacen.nainari@itson.mx',
      contrasena: 'demo1234',
    });

    expect(repositorio.iniciarSesion).toHaveBeenCalledWith('almacen.nainari@itson.mx', 'demo1234');
    expect(repositorio.buscarPerfil).toHaveBeenCalledWith('token-acceso', 'u1');
    expect(respuesta).toEqual({
      accessToken: 'token-acceso',
      refreshToken: 'token-renovacion',
      expiraEn: 1763000000,
      usuario: {
        id: 'u1',
        nombre: 'Almacén Náinari (demo)',
        email: 'almacen.nainari@itson.mx',
        rol: Rol.Almacenista,
        campusId: 1,
        campus: 'Náinari',
      },
    });
  });

  it('rechaza un usuario que no está registrado en la tabla usuarios', async () => {
    const servicio = crearServicio({ buscarPerfil: jest.fn().mockResolvedValue(null) });

    await expect(
      servicio.iniciar({ usuario: 'nadie@itson.mx', contrasena: 'demo1234' }),
    ).rejects.toMatchObject({
      codigo: 'USUARIO_NO_REGISTRADO',
      estadoHttp: HttpStatus.FORBIDDEN,
    });
  });

  it('rechaza un usuario inactivo aunque sus credenciales sean válidas', async () => {
    const servicio = crearServicio({
      buscarPerfil: jest.fn().mockResolvedValue({ ...PERFIL, activo: false }),
    });

    await expect(
      servicio.iniciar({ usuario: 'inactivo@itson.mx', contrasena: 'demo1234' }),
    ).rejects.toMatchObject({
      codigo: 'USUARIO_INACTIVO',
      estadoHttp: HttpStatus.FORBIDDEN,
    });
  });

  it('deja pasar el error de credenciales inválidas del repositorio', async () => {
    const error = new ErrorNegocio(
      'CREDENCIALES_INVALIDAS',
      'El usuario o la contraseña no son correctos.',
      HttpStatus.UNAUTHORIZED,
    );
    const servicio = crearServicio({ iniciarSesion: jest.fn().mockRejectedValue(error) });

    await expect(
      servicio.iniciar({ usuario: 'almacen.nainari@itson.mx', contrasena: 'mala' }),
    ).rejects.toBe(error);
  });

  it('renueva la sesión y vuelve a leer el perfil', async () => {
    const repositorio = {
      renovar: jest.fn().mockResolvedValue(TOKENS),
      buscarPerfil: jest.fn().mockResolvedValue(PERFIL),
    };

    const respuesta = await crearServicio(repositorio).renovar({
      refreshToken: 'token-renovacion',
    });

    expect(repositorio.renovar).toHaveBeenCalledWith('token-renovacion');
    expect(respuesta.usuario.nombre).toBe('Almacén Náinari (demo)');
  });
});
